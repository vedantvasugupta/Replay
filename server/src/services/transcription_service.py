from __future__ import annotations

import logging

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

logger = logging.getLogger("uvicorn")


class TranscriptionService:
    def __init__(self, gemini: GeminiService, storage: StorageService) -> None:
        self._gemini = gemini
        self._storage = storage

    async def process_session(self, db: AsyncSession, session_id: int) -> None:
        """Process a session with partial success handling."""
        logger.info(f"🎬 [SESSION {session_id}] Starting session processing")

        session_stmt = select(Session).where(Session.id == session_id).options(
            selectinload(Session.audio_asset),
            selectinload(Session.transcript),
            selectinload(Session.summary),
        )
        session_obj = await db.scalar(session_stmt)
        if not session_obj:
            logger.error(f"❌ [SESSION {session_id}] Session not found in database")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
        if not session_obj.audio_asset:
            logger.error(f"❌ [SESSION {session_id}] Session missing audio asset")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Session missing audio asset")

        asset: AudioAsset = session_obj.audio_asset
        path = self._storage.resolve_asset_path(asset)
        logger.info(f"📁 [SESSION {session_id}] Audio file path: {path}")

        if not path.exists():
            logger.error(f"❌ [SESSION {session_id}] Audio file not found at path: {path}")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Audio file missing")

        # Check if we already have transcript and summary (idempotency check)
        if session_obj.transcript and session_obj.summary:
            logger.info(f"✅ [SESSION {session_id}] Already has transcript and summary, marking as ready")
            session_obj.status = SessionStatus.ready
            db.add(session_obj)
            await db.commit()
            return

        # Use combined API call for efficiency (1 API call instead of 2)
        logger.info(f"🚀 [SESSION {session_id}] Starting Gemini transcription and analysis")
        try:
            result = await self._gemini.transcribe_and_analyze(path, asset.mime)
            logger.info(f"✅ [SESSION {session_id}] Gemini processing completed successfully")
        except Exception as e:
            # If API call fails, mark session as failed but don't raise
            logger.error(f"❌ [SESSION {session_id}] Gemini API error: {e}")
            session_obj.status = SessionStatus.failed
            db.add(session_obj)
            await db.commit()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Gemini API error: {str(e)}"
            ) from e

        # Save transcript first (partial success handling)
        if not session_obj.transcript:
            logger.info(f"💾 [SESSION {session_id}] Saving transcript to database")
            transcript = Transcript(
                session_id=session_obj.id,
                text=result["text"],
                segments_json=result.get("segments", []),
                speakers_json=result.get("speakers", []),
            )
            db.add(transcript)
            try:
                await db.commit()
                await db.refresh(session_obj)
                logger.info(f"✅ [SESSION {session_id}] Transcript saved successfully")
            except Exception as e:
                logger.error(f"❌ [SESSION {session_id}] Failed to save transcript: {e}")
                await db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Failed to save transcript: {str(e)}"
                ) from e

        # Update title if provided and not already set
        if result.get("title") and (not session_obj.title or session_obj.title.startswith("Session ")):
            logger.info(f"📝 [SESSION {session_id}] Updating title to: '{result['title']}'")
            session_obj.title = result["title"]
            db.add(session_obj)
            await db.commit()
            await db.refresh(session_obj)

        # Save summary (partial success handling)
        if not session_obj.summary:
            logger.info(f"💾 [SESSION {session_id}] Saving summary to database")
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
                logger.info(f"✅ [SESSION {session_id}] Summary saved successfully")
            except Exception as e:
                logger.warning(f"⚠️ [SESSION {session_id}] Failed to save summary: {e}")
                await db.rollback()
                # Don't fail completely if summary fails - we have transcript
                pass

        # Mark as ready only if both transcript and summary exist
        if session_obj.transcript and session_obj.summary:
            logger.info(f"🎉 [SESSION {session_id}] Processing complete! Marking as ready")
            session_obj.status = SessionStatus.ready
        else:
            logger.warning(f"⚠️ [SESSION {session_id}] Missing transcript or summary, keeping as processing")
            session_obj.status = SessionStatus.processing
        db.add(session_obj)
        await db.commit()
        logger.info(f"✅ [SESSION {session_id}] Session status updated: {session_obj.status}")
