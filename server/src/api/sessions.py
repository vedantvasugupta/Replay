from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models.entities import AudioAsset, Session, User
from ..schemas.session import (
    ChatRequest,
    ChatResponse,
    IngestRequest,
    SessionDetailResponse,
    SessionSummarySchema,
)
from ..services.chat import ChatService
from ..services.gemini import GeminiService
from ..services.jobs import jobs_service
from .deps import get_current_user, get_db

router = APIRouter(tags=["sessions"])


@router.get("/sessions")
async def list_sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[SessionSummarySchema]:
    result = await db.execute(
        select(Session)
        .where(Session.user_id == user.id)
        .order_by(Session.created_at.desc())
    )
    sessions = result.scalars().all()
    return [
        SessionSummarySchema(
            id=session.id,
            created_at=session.created_at,
            status=session.status,
            duration_sec=session.duration_sec,
        )
        for session in sessions
    ]


@router.post("/ingest")
async def ingest(
    payload: IngestRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    asset_result = await db.execute(
        select(AudioAsset).where(AudioAsset.id == payload.assetId, AudioAsset.user_id == user.id)
    )
    asset = asset_result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")
    session = Session(user_id=user.id, audio_asset_id=asset.id, status="uploaded")
    db.add(session)
    await db.commit()
    await db.refresh(session)
    await jobs_service.enqueue_transcription(session.id)
    await jobs_service.start()
    return {"sessionId": session.id, "status": "processing"}


@router.get("/session/{session_id}", response_model=SessionDetailResponse)
async def get_session(
    session_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SessionDetailResponse:
    result = await db.execute(
        select(Session)
        .options(
            selectinload(Session.transcript),
            selectinload(Session.summary),
        )
        .where(Session.id == session_id, Session.user_id == user.id)
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
    summary = None
    if session.summary:
        summary = {
            "summary": session.summary.summary,
            "action_items": session.summary.action_items_json or [],
            "timeline": session.summary.timeline_json or [],
            "decisions": session.summary.decisions_json or [],
        }
    segments = None
    if session.transcript and session.transcript.segments_json:
        segments = session.transcript.segments_json
    return SessionDetailResponse(
        meta=SessionSummarySchema(
            id=session.id,
            created_at=session.created_at,
            status=session.status,
            duration_sec=session.duration_sec,
        ),
        transcript=session.transcript.text if session.transcript else None,
        segments=segments,
        summary=summary,
    )


@router.post("/session/{session_id}/chat", response_model=ChatResponse)
async def chat(
    session_id: str,
    payload: ChatRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ChatResponse:
    result = await db.execute(select(Session.id).where(Session.id == session_id, Session.user_id == user.id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
    gemini = GeminiService()
    service = ChatService(db, gemini)
    data = await service.ask(session_id, payload.message)
    return ChatResponse(content=data["answer"], citations=data["citations"])
