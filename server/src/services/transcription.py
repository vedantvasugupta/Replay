from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.entities import Session, Summary, Transcript
from .gemini import GeminiService


class TranscriptionService:
    def __init__(self, db: AsyncSession, gemini: GeminiService) -> None:
        self.db = db
        self.gemini = gemini

    async def process_session(self, session_id: str) -> None:
        result = await self.db.execute(
            select(Session)
            .options(selectinload(Session.audio_asset))
            .where(Session.id == session_id)
        )
        session = result.scalar_one_or_none()
        if not session:
            return
        session.status = "processing"
        await self.db.commit()

        transcript_payload = await self.gemini.transcribe(session.audio_asset.path)
        transcript_text = transcript_payload.get("text", "")
        segments = transcript_payload.get("segments", [])

        summary_payload = await self.gemini.summarize(transcript_text)

        transcript = Transcript(
            session_id=session.id,
            text=transcript_text,
            segments_json=segments,
        )
        summary = Summary(
            session_id=session.id,
            summary=summary_payload.get("summary", ""),
            action_items_json=summary_payload.get("action_items", []),
            timeline_json=summary_payload.get("timeline", []),
            decisions_json=summary_payload.get("decisions", []),
        )
        self.db.add_all([transcript, summary])
        if not session.duration_sec:
            approx_duration = max(len(transcript_text.split()) // 2, 30)
            session.duration_sec = approx_duration
        session.status = "ready"
        await self.db.commit()
