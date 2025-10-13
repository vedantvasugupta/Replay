from __future__ import annotations

import asyncio
import json
from typing import Any, Callable

from sqlalchemy import select

from sqlalchemy.ext.asyncio import AsyncSession

from ..models.job import Job
from ..models.session import Session


class JobsService:
    def __init__(self) -> None:
        self._queue: asyncio.Queue[int] = asyncio.Queue()

    async def enqueue_transcription(self, db: AsyncSession, session: Session) -> Job:
        job = Job(job_type="transcription", session_id=session.id, payload=json.dumps({"session_id": session.id}))
        db.add(job)
        await db.commit()
        await db.refresh(job)
        await self._queue.put(job.id)
        return job

    async def reserve_next(self, db: AsyncSession) -> Job | None:
        job_obj: Job | None = None
        try:
            job_id = self._queue.get_nowait()
        except asyncio.QueueEmpty:
            stmt = select(Job).where(Job.status == "pending").order_by(Job.created_at.asc())
            job_obj = await db.scalar(stmt)
        else:
            job_obj = await db.get(Job, job_id)
        if not job_obj:
            return None
        job_obj.status = "processing"
        job_obj.attempts += 1
        db.add(job_obj)
        await db.commit()
        return job_obj

    async def mark_complete(self, db: AsyncSession, job: Job) -> None:
        job.status = "completed"
        db.add(job)
        await db.commit()

    async def mark_failed(self, db: AsyncSession, job: Job, error: str, max_retries: int = 3) -> None:
        """Mark job as failed, or retry if attempts are below max_retries."""
        if job.attempts < max_retries:
            # Reset to pending for retry
            job.status = "pending"
            job.error = f"Retry {job.attempts}/{max_retries}: {error[:200]}"
            db.add(job)
            await db.commit()
            # Re-enqueue for retry
            await self._queue.put(job.id)
        else:
            # Max retries exceeded, mark as failed
            job.status = "failed"
            job.error = error[:255]
            db.add(job)
            await db.commit()

    async def cancel_session_jobs(self, db: AsyncSession, session_id: int) -> int:
        """Cancel all pending/processing jobs for a session. Returns count of cancelled jobs."""
        stmt = select(Job).where(
            Job.session_id == session_id,
            Job.status.in_(["pending", "processing"])
        )
        result = await db.execute(stmt)
        jobs = result.scalars().all()

        cancelled_count = 0
        for job in jobs:
            job.status = "failed"
            job.error = "Cancelled by user (session deleted)"
            db.add(job)
            cancelled_count += 1

        if cancelled_count > 0:
            await db.commit()

        return cancelled_count

    async def run_worker(
        self,
        db_factory: Callable[[], AsyncSession],
        handler: Callable[[AsyncSession, Job], Awaitable[None]],
        poll_interval: int = 5,
    ) -> None:
        while True:
            async with db_factory() as session:
                job = await self.reserve_next(session)
                if not job:
                    await asyncio.sleep(poll_interval)
                    continue
                try:
                    await handler(session, job)
                except Exception as e:  # noqa: BLE001
                    error_msg = f"{type(e).__name__}: {str(e)}"
                    await self.mark_failed(session, job, error_msg)
                    # Add exponential backoff for retries
                    if job.attempts < 3:
                        await asyncio.sleep(min(2 ** job.attempts, 60))  # 2s, 4s, 8s backoff
                else:
                    await self.mark_complete(session, job)
