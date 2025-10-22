from __future__ import annotations

import asyncio
import contextlib
import json
from dataclasses import dataclass, field
from typing import cast

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession

from .api import auth, sessions, uploads
from .core.config import get_settings
from .core.db import async_session_factory
from .models.job import Job
from .models.session import Session
from .models.enums import SessionStatus
from .services.auth_service import AuthService
from .services.chat_service import ChatService
from .services.gemini_service import GeminiService
from .services.jobs_service import JobsService
from .services.session_service import SessionService
from .services.storage_service import StorageService
from .services.transcription_service import TranscriptionService


@dataclass
class AppState:
    auth_service: AuthService
    storage_service: StorageService
    gemini_service: GeminiService
    transcription_service: TranscriptionService
    session_service: SessionService
    chat_service: ChatService
    jobs_service: JobsService
    workers: list[asyncio.Task[None]] = field(default_factory=list)


def get_app_state() -> AppState:
    app = cast(FastAPI, app_instance)
    return cast(AppState, app.state.container)


def create_app() -> FastAPI:
    app = FastAPI(title="Replay API", version="0.1.0")

    settings = get_settings()
    cors_origins = ["*"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    storage_service = StorageService()
    gemini_service = GeminiService()
    transcription_service = TranscriptionService(gemini_service, storage_service)
    session_service = SessionService()
    chat_service = ChatService(gemini_service)
    auth_service = AuthService()
    jobs_service = JobsService()

    app.state.container = AppState(
        auth_service=auth_service,
        storage_service=storage_service,
        gemini_service=gemini_service,
        transcription_service=transcription_service,
        session_service=session_service,
        chat_service=chat_service,
        jobs_service=jobs_service,
    )

    app.include_router(auth.router)
    app.include_router(uploads.router)
    app.include_router(sessions.router)

    @app.on_event("startup")
    async def start_worker() -> None:
        import logging
        from sqlalchemy import select
        logger = logging.getLogger("uvicorn")
        concurrency = max(1, settings.background_worker_concurrency)
        logger.info(f"🚀 Starting background workers (concurrency={concurrency})...")

        state = get_app_state()

        # Load existing pending jobs into the queue
        async with async_session_factory() as db:
            stmt = select(Job).where(Job.status == "pending")
            result = await db.execute(stmt)
            pending_jobs = result.scalars().all()

            for job in pending_jobs:
                await state.jobs_service._queue.put(job.id)

            logger.info(f"📋 Loaded {len(pending_jobs)} pending jobs into queue")

        async def handler(db: AsyncSession, job: Job) -> None:
            payload = json.loads(job.payload)
            session_id = payload["session_id"]
            logger.info(f"Processing job {job.id} for session {session_id}")
            try:
                # Add 10-minute timeout to prevent workers from getting stuck
                await asyncio.wait_for(
                    state.transcription_service.process_session(db, session_id),
                    timeout=600.0  # 10 minutes
                )
                logger.info(f"✅ Job {job.id} completed successfully")
            except asyncio.TimeoutError:
                logger.error(f"❌ Job {job.id} timed out after 10 minutes")
                session_obj = await db.get(Session, session_id)
                if session_obj:
                    session_obj.status = SessionStatus.failed
                    db.add(session_obj)
                    await db.commit()
                raise
            except Exception as e:
                logger.error(f"❌ Job {job.id} failed: {e}")
                session_obj = await db.get(Session, session_id)
                if session_obj:
                    session_obj.status = SessionStatus.failed
                    db.add(session_obj)
                    await db.commit()
                raise

        state.workers = []
        for idx in range(concurrency):
            worker_task = asyncio.create_task(
                state.jobs_service.run_worker(
                    async_session_factory,
                    handler,
                    poll_interval=settings.background_poll_interval,
                )
            )
            state.workers.append(worker_task)
            logger.info(f"✅ Background worker #{idx + 1} started")

    @app.on_event("shutdown")
    async def shutdown_worker() -> None:
        state = get_app_state()
        for worker in state.workers:
            worker.cancel()
        for worker in state.workers:
            with contextlib.suppress(asyncio.CancelledError):
                await worker
        state.workers.clear()

    return app


app_instance = create_app()
app = app_instance

__all__ = ["app", "get_app_state"]
