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
            # Pass duration_sec for dynamic timeout calculation
            result = await self._gemini.transcribe_and_analyze(path, asset.mime, session_obj.duration_sec)
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

        # Update title if provided and current title looks auto-generated
        # We replace the title only if it's timestamp-based or auto-generated
        should_update_title = False
        if result.get("title") and session_obj.title:
            # Check if title looks auto-generated
            import re
            # Pattern 1: "Session YYYY-MM-DD HH:MM" (default format)
            # Pattern 2: Timestamp-like filenames: "2025-01-22_14-30-45", "recording_1234567890", etc.
            # Pattern 3: Just numbers or UUID-like strings
            # Pattern 4: Generic names like "audio.m4a", "recording.mp3" (without extension already)
            is_auto_generated = (
                session_obj.title.startswith("Session ") or
                bool(re.match(r'^\d{4}-\d{2}-\d{2}[_-]\d{2}[:-]\d{2}[:-]\d{2}', session_obj.title)) or
                bool(re.match(r'^(recording|audio|file|untitled|new recording)[_-]?\d*$', session_obj.title, re.IGNORECASE)) or
                bool(re.match(r'^\d{10,}$', session_obj.title)) or  # Unix timestamp
                bool(re.match(r'^[a-f0-9]{8,}$', session_obj.title, re.IGNORECASE))  # UUID-like
            )
            should_update_title = is_auto_generated

        if should_update_title:
            logger.info(f"📝 [SESSION {session_id}] Auto-generated title detected: '{session_obj.title}'. Updating to: '{result['title']}'")
            session_obj.title = result["title"]
            db.add(session_obj)
            await db.commit()
            await db.refresh(session_obj)
        elif result.get("title") and session_obj.title:
            logger.info(f"📝 [SESSION {session_id}] Keeping user-provided title: '{session_obj.title}' (AI suggested: '{result['title']}')")

        # Save summary (partial success handling)
        if not session_obj.summary:
            logger.info(f"💾 [SESSION {session_id}] Saving summary to database")
            summary_data = result.get("summary", {})

            # Validate summary data structure
            if not isinstance(summary_data, dict):
                logger.error(f"❌ [SESSION {session_id}] Invalid summary data type: {type(summary_data)}, expected dict")
                summary_data = {
                    "summary": "",
                    "action_items": [],
                    "timeline": [],
                    "decisions": [],
                }

            summary_text = summary_data.get("summary", "")
            action_items = summary_data.get("action_items", [])
            timeline = summary_data.get("timeline", [])
            decisions = summary_data.get("decisions", [])

            # Ensure all values are of correct type
            if not isinstance(summary_text, str):
                logger.warning(f"⚠️ [SESSION {session_id}] Summary text is not a string, converting: {type(summary_text)}")
                summary_text = str(summary_text) if summary_text else ""

            if not isinstance(action_items, list):
                logger.warning(f"⚠️ [SESSION {session_id}] Action items is not a list, converting: {type(action_items)}")
                action_items = []

            if not isinstance(timeline, list):
                logger.warning(f"⚠️ [SESSION {session_id}] Timeline is not a list, converting: {type(timeline)}")
                timeline = []

            if not isinstance(decisions, list):
                logger.warning(f"⚠️ [SESSION {session_id}] Decisions is not a list, converting: {type(decisions)}")
                decisions = []

            logger.info(f"📊 [SESSION {session_id}] Summary data: text={len(summary_text)} chars, actions={len(action_items)}, timeline={len(timeline)}, decisions={len(decisions)}")

            summary = Summary(
                session_id=session_obj.id,
                summary=summary_text,
                action_items_json=action_items,
                timeline_json=timeline,
                decisions_json=decisions,
            )
            db.add(summary)
            try:
                await db.commit()
                await db.refresh(session_obj)
                logger.info(f"✅ [SESSION {session_id}] Summary saved successfully")
            except Exception as e:
                import traceback
                error_details = traceback.format_exc()
                logger.error(f"❌ [SESSION {session_id}] Failed to save summary: {e}")
                logger.error(f"❌ [SESSION {session_id}] Error details:\n{error_details}")
                logger.error(f"❌ [SESSION {session_id}] Summary data that failed: summary_text_len={len(summary_text)}, action_items={action_items}, timeline={timeline}, decisions={decisions}")
                await db.rollback()
                # Don't fail completely if summary fails - we have transcript
                # But log detailed error for debugging
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
