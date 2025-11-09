from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.deps import get_current_user, get_db_session
from ..models.user import User
from ..schemas.chat import ChatMessageRequest, ChatMessageResponse, Citation
from ..schemas.session import MessageRead, SessionDetail, SessionListItem, UpdateSessionTitleRequest
from ..services.chat_service import ChatService
from ..services.jobs_service import JobsService
from ..services.session_service import SessionService
from ..services.storage_service import StorageService


def get_session_service() -> SessionService:
    from ..app import get_app_state

    return get_app_state().session_service


def get_chat_service() -> ChatService:
    from ..app import get_app_state

    return get_app_state().chat_service


def get_jobs_service() -> JobsService:
    from ..app import get_app_state

    return get_app_state().jobs_service


def get_storage_service() -> StorageService:
    from ..app import get_app_state

    return get_app_state().storage_service


router = APIRouter(tags=["sessions"])


@router.get("/health/worker")
async def check_worker_health(
    db: AsyncSession = Depends(get_db_session),
    jobs_service: JobsService = Depends(get_jobs_service),
):
    """Debug endpoint to check worker status and pending jobs."""
    from sqlalchemy import select, func
    from ..models.job import Job
    from ..app import get_app_state

    state = get_app_state()

    # Count jobs by status
    status_counts = {}
    for status in ["pending", "processing", "completed", "failed"]:
        stmt = select(func.count()).select_from(Job).where(Job.status == status)
        result = await db.execute(stmt)
        status_counts[status] = result.scalar_one()

    # Get recent pending jobs
    stmt = select(Job).where(Job.status == "pending").order_by(Job.created_at.desc()).limit(5)
    result = await db.execute(stmt)
    recent_pending = result.scalars().all()

    return {
        "worker_running": state.worker is not None and not state.worker.done(),
        "worker_cancelled": state.worker.cancelled() if state.worker else False,
        "queue_size": jobs_service._queue.qsize(),
        "has_gemini_key": bool(state.gemini_service.api_key),
        "job_counts": status_counts,
        "recent_pending_jobs": [
            {
                "id": job.id,
                "session_id": job.session_id,
                "attempts": job.attempts,
                "created_at": job.created_at.isoformat(),
            }
            for job in recent_pending
        ],
    }


@router.post("/health/requeue-pending")
async def requeue_pending_jobs(
    db: AsyncSession = Depends(get_db_session),
    jobs_service: JobsService = Depends(get_jobs_service),
):
    """Manually re-queue all pending jobs. Use this if worker is stuck."""
    from sqlalchemy import select
    from ..models.job import Job

    stmt = select(Job).where(Job.status == "pending")
    result = await db.execute(stmt)
    jobs = result.scalars().all()

    count = 0
    for job in jobs:
        await jobs_service._queue.put(job.id)
        count += 1

    return {
        "requeued_count": count,
        "message": f"Re-queued {count} pending jobs",
    }


@router.get("/health/check-sessions")
async def check_sessions_status(
    db: AsyncSession = Depends(get_db_session),
    limit: int = 10,
):
    """Check status of recent sessions including summary generation."""
    from sqlalchemy import select
    from ..models.session import Session
    from ..models.summary import Summary
    from ..models.job import Job

    # Get latest sessions with summary info
    stmt = (
        select(Session)
        .options(selectinload(Session.summary))
        .order_by(Session.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    sessions = result.scalars().all()

    session_info = []
    for session in sessions:
        # Get jobs for this session
        job_stmt = (
            select(Job)
            .where(Job.session_id == session.id)
            .order_by(Job.created_at.desc())
        )
        job_result = await db.execute(job_stmt)
        jobs = job_result.scalars().all()

        session_info.append({
            "id": session.id,
            "title": session.title,
            "status": session.status.value,
            "created_at": session.created_at.isoformat(),
            "has_summary": session.summary is not None,
            "jobs": [
                {
                    "id": job.id,
                    "type": job.job_type.value,
                    "status": job.status.value,
                    "attempts": job.attempts,
                    "error": job.error[:100] if job.error else None,
                }
                for job in jobs
            ],
        })

    return {
        "sessions": session_info,
        "total_checked": len(sessions),
    }


@router.post("/health/retrigger-summaries")
async def retrigger_summaries(
    db: AsyncSession = Depends(get_db_session),
    jobs_service: JobsService = Depends(get_jobs_service),
    session_ids: list[int] | None = None,
    limit: int = 10,
):
    """Re-trigger summary generation for sessions without summaries."""
    from sqlalchemy import select
    from ..models.session import Session
    from ..models.summary import Summary
    from ..models.job import Job, JobType, JobStatus

    # Get sessions without summaries
    if session_ids:
        stmt = (
            select(Session)
            .options(selectinload(Session.summary))
            .where(Session.id.in_(session_ids))
        )
    else:
        stmt = (
            select(Session)
            .options(selectinload(Session.summary))
            .order_by(Session.created_at.desc())
            .limit(limit)
        )

    result = await db.execute(stmt)
    sessions = result.scalars().all()

    retriggered = []
    for session in sessions:
        if session.summary is None:
            # Create a new summary job
            new_job = Job(
                session_id=session.id,
                job_type=JobType.summarize,
                status=JobStatus.pending,
            )
            db.add(new_job)
            await db.flush()

            # Queue the job
            await jobs_service._queue.put(new_job.id)

            retriggered.append({
                "session_id": session.id,
                "job_id": new_job.id,
                "title": session.title,
            })

    await db.commit()

    return {
        "retriggered_count": len(retriggered),
        "sessions": retriggered,
        "message": f"Re-triggered summary generation for {len(retriggered)} sessions",
    }


@router.get("/sessions", response_model=list[SessionListItem])
async def list_sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    session_service: SessionService = Depends(get_session_service),
) -> list[SessionListItem]:
    return await session_service.list_sessions(db, user.id)


@router.get("/session/{session_id}", response_model=SessionDetail)
async def get_session(
    session_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    session_service: SessionService = Depends(get_session_service),
) -> SessionDetail:
    return await session_service.get_detail(db, user.id, session_id)


@router.patch("/session/{session_id}/title")
async def update_session_title(
    session_id: int,
    payload: UpdateSessionTitleRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    session_service: SessionService = Depends(get_session_service),
):
    await session_service.update_title(db, user.id, session_id, payload.title)
    return {"success": True, "title": payload.title}


@router.delete("/session/{session_id}")
async def delete_session(
    session_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    session_service: SessionService = Depends(get_session_service),
    jobs_service: JobsService = Depends(get_jobs_service),
    storage_service: StorageService = Depends(get_storage_service),
):
    await session_service.delete_session(db, user.id, session_id, jobs_service, storage_service)
    return {"success": True, "message": "Session deleted successfully"}


@router.get("/session/{session_id}/messages", response_model=list[MessageRead])
async def get_session_messages(
    session_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    session_service: SessionService = Depends(get_session_service),
) -> list[MessageRead]:
    return await session_service.get_messages(db, user.id, session_id)


@router.post("/session/{session_id}/chat", response_model=ChatMessageResponse)
async def chat_with_session(
    session_id: int,
    payload: ChatMessageRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    chat_service: ChatService = Depends(get_chat_service),
) -> ChatMessageResponse:
    user_msg, assistant_msg, citations = await chat_service.answer(db, session_id, user.id, payload.message)
    return ChatMessageResponse(
        assistant_message=assistant_msg.content,
        citations=[Citation(**citation) for citation in citations],
    )
