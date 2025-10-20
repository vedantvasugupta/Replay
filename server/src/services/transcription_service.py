from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models.session import Session
from ..models.enums import SessionStatus
from ..models.transcript import Transcript
from ..models.summary import Summary
from ..models.audio_asset import AudioAsset
from .gemini_service import GeminiService
from .storage_service import StorageService


class TranscriptionService:
    def __init__(self, gemini: GeminiService, storage: StorageService) -> None:
        self._gemini = gemini
        self._storage = storage

    async def process_session(self, db: AsyncSession, session_id: int) -> None:
        """Process a session with partial success handling."""
        session_stmt = select(Session).where(Session.id == session_id).options(
            selectinload(Session.audio_asset),
            selectinload(Session.transcript),
            selectinload(Session.summary),
        )
        session_obj = await db.scalar(session_stmt)
        if not session_obj:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
        if not session_obj.audio_asset:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Session missing audio asset")

        asset: AudioAsset = session_obj.audio_asset
        path = self._storage.resolve_asset_path(asset)
        if not path.exists():
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audio file missing")

        # Check if we already have transcript and summary (idempotency check)
        if session_obj.transcript and session_obj.summary:
            session_obj.status = SessionStatus.ready
            db.add(session_obj)
            await db.commit()
            return

        # Use combined API call for efficiency (1 API call instead of 2)
        try:
            result = await self._gemini.transcribe_and_analyze(path, asset.mime)
        except Exception as e:
            # If API call fails, mark session as failed but don't raise
            session_obj.status = SessionStatus.failed
            db.add(session_obj)
            await db.commit()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Gemini API error: {str(e)}"
            ) from e

        # Save transcript first (partial success handling)
        if not session_obj.transcript:
            transcript = Transcript(
                session_id=session_obj.id,
                text=result["text"],
                segments_json=result.get("segments", []),
            )
            db.add(transcript)
            try:
                await db.commit()
                await db.refresh(session_obj)
            except Exception as e:
                await db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Failed to save transcript: {str(e)}"
                ) from e

        # Update title if provided and not already set
        if result.get("title") and (not session_obj.title or session_obj.title.startswith("Session ")):
            session_obj.title = result["title"]
            db.add(session_obj)
            await db.commit()
            await db.refresh(session_obj)

        # Save summary (partial success handling)
        if not session_obj.summary:
            summary_data = result.get("summary", {})
            summary = Summary(
                session_id=session_obj.id,
                summary=summary_data.get("summary", ""),
                action_items_json=summary_data.get("action_items", []),
                timeline_json=summary_data.get("timeline", []),
                decisions_json=summary_data.get("decisions", []),
            )
            db.add(summary)
            try:
                await db.commit()
                await db.refresh(session_obj)
            except Exception as e:
                await db.rollback()
                # Don't fail completely if summary fails - we have transcript
                pass

        # Mark as ready only if both transcript and summary exist
        if session_obj.transcript and session_obj.summary:
            session_obj.status = SessionStatus.ready
        else:
            session_obj.status = SessionStatus.processing
        db.add(session_obj)
        await db.commit()
