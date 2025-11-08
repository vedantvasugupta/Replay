"""
Debug and fix sessions with missing summaries.

This script:
1. Finds sessions with transcripts but no summaries
2. Re-triggers summary generation for those sessions

Usage:
    python -m scripts.fix_missing_summaries [--limit=10] [--dry-run]
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, selectinload

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models.session import Session
from src.models.transcript import Transcript
from src.models.summary import Summary
from src.models.enums import SessionStatus
from src.core.config import get_settings
from src.services.gemini_service import GeminiService
from src.services.storage_service import StorageService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


async def find_sessions_without_summaries(db: AsyncSession, limit: int = 10):
    """Find sessions that have transcripts but no summaries."""
    stmt = (
        select(Session)
        .outerjoin(Transcript, Session.id == Transcript.session_id)
        .outerjoin(Summary, Session.id == Summary.session_id)
        .where(Transcript.id.isnot(None))  # Has transcript
        .where(Summary.id.is_(None))  # No summary
        .order_by(Session.created_at.desc())
        .limit(limit)
        .options(
            selectinload(Session.transcript),
            selectinload(Session.summary),
            selectinload(Session.audio_asset)
        )
    )

    result = await db.execute(stmt)
    sessions = result.scalars().all()
    return sessions


async def regenerate_summary(db: AsyncSession, session_obj: Session, gemini: GeminiService, storage: StorageService):
    """Regenerate summary for a session that has a transcript."""
    logger.info(f"🔄 [SESSION {session_obj.id}] Regenerating summary...")

    if not session_obj.transcript:
        logger.error(f"❌ [SESSION {session_obj.id}] No transcript found!")
        return False

    if session_obj.summary:
        logger.warning(f"⚠️ [SESSION {session_obj.id}] Already has summary, skipping")
        return False

    try:
        # Get the transcript text
        transcript_text = session_obj.transcript.text
        logger.info(f"📝 [SESSION {session_obj.id}] Transcript length: {len(transcript_text)} chars")

        # Generate summary using Gemini
        logger.info(f"🤖 [SESSION {session_obj.id}] Calling Gemini to generate summary...")
        summary_result = await gemini.summarize(transcript_text)

        # Create and save summary
        summary = Summary(
            session_id=session_obj.id,
            summary=summary_result.get("summary", ""),
            action_items_json=summary_result.get("action_items", []),
            timeline_json=summary_result.get("timeline", []),
            decisions_json=summary_result.get("decisions", []),
        )

        db.add(summary)
        await db.commit()
        await db.refresh(session_obj)

        # Update session status to ready if it was processing
        if session_obj.status == SessionStatus.processing:
            session_obj.status = SessionStatus.ready
            db.add(session_obj)
            await db.commit()
            logger.info(f"✅ [SESSION {session_obj.id}] Status updated to ready")

        logger.info(f"✅ [SESSION {session_obj.id}] Summary regenerated successfully!")
        return True

    except Exception as e:
        logger.error(f"❌ [SESSION {session_obj.id}] Failed to regenerate summary: {e}")
        await db.rollback()
        return False


async def main():
    """Main entry point."""
    # Parse arguments
    limit = 10
    dry_run = False

    for arg in sys.argv[1:]:
        if arg.startswith("--limit="):
            limit = int(arg.split("=")[1])
        elif arg == "--dry-run":
            dry_run = True

    logger.info("🚀 Starting summary regeneration script")
    logger.info(f"📊 Settings: limit={limit}, dry_run={dry_run}")

    # Get database URL from settings
    settings = get_settings()
    database_url = settings.database_url

    # Convert postgres:// to postgresql+asyncpg://
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif database_url.startswith("sqlite"):
        # For SQLite, use aiosqlite
        if not database_url.startswith("sqlite+aiosqlite"):
            database_url = database_url.replace("sqlite://", "sqlite+aiosqlite://", 1)

    logger.info(f"🔌 Connecting to database...")
    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    # Initialize services
    gemini = GeminiService()
    storage = StorageService()

    async with async_session() as db:
        # Find sessions without summaries
        logger.info(f"🔍 Searching for sessions with transcripts but no summaries (limit={limit})...")
        sessions = await find_sessions_without_summaries(db, limit)

        logger.info(f"📋 Found {len(sessions)} sessions without summaries:\n")

        if not sessions:
            logger.info("✅ All sessions have summaries!")
            await engine.dispose()
            return

        # Display summary
        for s in sessions:
            has_transcript = "✅" if s.transcript else "❌"
            has_summary = "✅" if s.summary else "❌"
            transcript_len = len(s.transcript.text) if s.transcript else 0
            logger.info(
                f"  Session {s.id:3d}: {s.title[:50]:50s} | "
                f"Status: {s.status.value:10s} | "
                f"Transcript: {has_transcript} ({transcript_len:6d} chars) | "
                f"Summary: {has_summary}"
            )

        if dry_run:
            logger.info("\n🏃 Dry run mode - not regenerating summaries")
            await engine.dispose()
            return

        # Regenerate summaries
        logger.info(f"\n🔧 Starting summary regeneration for {len(sessions)} sessions...\n")
        success_count = 0
        fail_count = 0

        for idx, session_obj in enumerate(sessions, 1):
            logger.info(f"\n[{idx}/{len(sessions)}] Processing session {session_obj.id}...")
            success = await regenerate_summary(db, session_obj, gemini, storage)
            if success:
                success_count += 1
            else:
                fail_count += 1

            # Add a small delay between API calls to avoid rate limiting
            if idx < len(sessions):
                await asyncio.sleep(2)

        logger.info(f"\n✅ Summary regeneration complete!")
        logger.info(f"   Successful: {success_count}")
        logger.info(f"   Failed: {fail_count}")

    await engine.dispose()
    logger.info("🎉 Script finished!")


if __name__ == "__main__":
    asyncio.run(main())
