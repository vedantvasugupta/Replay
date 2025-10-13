from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from fastapi import HTTPException, status
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models.audio_asset import AudioAsset
from ..models.session import Session
from ..models.enums import SessionStatus
from ..schemas.session import (
    SessionDetail,
    SessionListItem,
    SessionMeta,
    SummaryRead,
    TranscriptRead,
    TranscriptSegment,
)


class SessionService:
    async def list_sessions(self, db: AsyncSession, user_id: int) -> list[SessionListItem]:
        stmt = (
            select(Session)
            .where(Session.user_id == user_id)
            .order_by(Session.created_at.desc())
        )
        result = await db.execute(stmt)
        sessions = result.scalars().all()
        return [SessionListItem.model_validate(session) for session in sessions]

    async def create_session(self, db: AsyncSession, user_id: int, asset: AudioAsset, duration: int | None, title: str | None) -> Session:
        session = Session(
            user_id=user_id,
            audio_asset_id=asset.id,
            status=SessionStatus.processing,
            duration_sec=duration,
            title=title or datetime.now(timezone.utc).strftime("Session %Y-%m-%d %H:%M"),
        )
        db.add(session)
        await db.commit()
        await db.refresh(session)
        return session

    async def get_detail(self, db: AsyncSession, user_id: int, session_id: int) -> SessionDetail:
        stmt = (
            select(Session)
            .where(Session.id == session_id, Session.user_id == user_id)
            .options(selectinload(Session.transcript), selectinload(Session.summary))
        )
        session_obj = await db.scalar(stmt)
        if not session_obj:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")

        meta = SessionMeta.model_validate(session_obj)
        transcript = None
        if session_obj.transcript:
            segments = [TranscriptSegment(**segment) for segment in session_obj.transcript.segments_json]
            transcript = TranscriptRead(text=session_obj.transcript.text, segments=segments)
        summary = (
            SummaryRead(
                summary=session_obj.summary.summary,
                action_items=session_obj.summary.action_items_json,
                timeline=session_obj.summary.timeline_json,
                decisions=session_obj.summary.decisions_json,
            )
            if session_obj.summary
            else None
        )
        return SessionDetail(meta=meta, transcript=transcript, summary=summary)

    async def update_title(self, db: AsyncSession, user_id: int, session_id: int, new_title: str) -> None:
        """Update session title."""
        stmt = select(Session).where(Session.id == session_id, Session.user_id == user_id)
        session_obj = await db.scalar(stmt)
        if not session_obj:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")

        session_obj.title = new_title
        db.add(session_obj)
        await db.commit()

    async def delete_session(self, db: AsyncSession, user_id: int, session_id: int, jobs_service: "JobsService") -> None:
        """Delete a session, cancel any processing jobs, and remove audio file."""
        # Load session with audio asset relationship
        stmt = (
            select(Session)
            .where(Session.id == session_id, Session.user_id == user_id)
            .options(selectinload(Session.audio_asset))
        )
        session_obj = await db.scalar(stmt)
        if not session_obj:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")

        # Cancel any pending/processing jobs
        await jobs_service.cancel_session_jobs(db, session_id)

        # Delete audio file from storage if it exists
        if session_obj.audio_asset and session_obj.audio_asset.path:
            audio_path = Path(session_obj.audio_asset.path)
            try:
                if audio_path.exists():
                    audio_path.unlink()
            except Exception:
                pass  # Continue with deletion even if file removal fails

        # Delete the session (cascades to transcript, summary, messages)
        await db.delete(session_obj)
        await db.commit()
