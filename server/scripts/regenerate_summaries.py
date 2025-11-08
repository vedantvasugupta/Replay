#!/usr/bin/env python3
"""
Regenerate summaries for sessions that have transcripts but no summaries.

This script is production-ready and can be run directly on the server.
It uses the existing transcript to generate summaries without re-transcribing.

Usage:
    python scripts/regenerate_summaries.py [--limit=10] [--dry-run]
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, selectinload

from src.models.session import Session
from src.models.transcript import Transcript
from src.models.summary import Summary
from src.models.enums import SessionStatus
from src.services.gemini_service import GeminiService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


async def find_broken_sessions(db: AsyncSession, limit: int = 10):
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
            selectinload(Session.summary)
        )
    )

    result = await db.execute(stmt)
    sessions = result.scalars().all()
    return sessions


async def regenerate_summary_from_transcript(db: AsyncSession, session_obj: Session, gemini: GeminiService) -> bool:
    """Generate summary from existing transcript."""
    session_id = session_obj.id

    logger.info(f"🔄 [SESSION {session_id}] Starting summary regeneration...")

    if not session_obj.transcript:
        logger.error(f"❌ [SESSION {session_id}] No transcript found!")
        return False

    if session_obj.summary:
        logger.warning(f"⚠️ [SESSION {session_id}] Already has summary, skipping")
        return False

    try:
        # Get the transcript text
        transcript_text = session_obj.transcript.text
        logger.info(f"📝 [SESSION {session_id}] Transcript length: {len(transcript_text)} characters")

        # Generate summary using Gemini
        logger.info(f"🤖 [SESSION {session_id}] Calling Gemini to generate summary...")
        summary_result = await gemini.summarize(transcript_text)

        # Validate result
        if not isinstance(summary_result, dict):
            logger.error(f"❌ [SESSION {session_id}] Invalid summary result type: {type(summary_result)}")
            return False

        summary_text = summary_result.get("summary", "")
        action_items = summary_result.get("action_items", [])
        timeline = summary_result.get("timeline", [])
        decisions = summary_result.get("decisions", [])

        # Ensure correct types
        if not isinstance(summary_text, str):
            summary_text = str(summary_text) if summary_text else ""
        if not isinstance(action_items, list):
            action_items = []
        if not isinstance(timeline, list):
            timeline = []
        if not isinstance(decisions, list):
            decisions = []

        logger.info(f"📊 [SESSION {session_id}] Summary generated: {len(summary_text)} chars, {len(action_items)} actions, {len(timeline)} timeline items, {len(decisions)} decisions")

        # Create and save summary
        summary = Summary(
            session_id=session_obj.id,
            summary=summary_text,
            action_items_json=action_items,
            timeline_json=timeline,
            decisions_json=decisions,
        )

        db.add(summary)
        await db.commit()
        await db.refresh(session_obj)

        logger.info(f"✅ [SESSION {session_id}] Summary saved to database")

        # Update session status to ready if it was processing
        if session_obj.status == SessionStatus.processing:
            session_obj.status = SessionStatus.ready
            db.add(session_obj)
            await db.commit()
            logger.info(f"✅ [SESSION {session_id}] Status updated to 'ready'")

        logger.info(f"🎉 [SESSION {session_id}] Summary regeneration complete!")
        return True

    except Exception as e:
        import traceback
        logger.error(f"❌ [SESSION {session_id}] Failed to regenerate summary: {e}")
        logger.error(f"❌ [SESSION {session_id}] Traceback:\n{traceback.format_exc()}")
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
        elif arg in ["-h", "--help"]:
            print(__doc__)
            return

    logger.info("="*80)
    logger.info("SUMMARY REGENERATION SCRIPT")
    logger.info("="*80)
    logger.info(f"📊 Configuration: limit={limit}, dry_run={dry_run}")
    logger.info("")

    # Get database URL from environment
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        logger.error("❌ DATABASE_URL environment variable not set!")
        sys.exit(1)

    # Convert postgres:// to postgresql+asyncpg://
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif database_url.startswith("sqlite"):
        if not database_url.startswith("sqlite+aiosqlite"):
            database_url = database_url.replace("sqlite://", "sqlite+aiosqlite://", 1)

    # Connect to database
    logger.info("🔌 Connecting to database...")
    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    # Initialize Gemini service
    gemini_api_key = os.getenv("GEMINI_API_KEY")
    if not gemini_api_key:
        logger.warning("⚠️ GEMINI_API_KEY not set - summary generation will use fallback mode")

    gemini = GeminiService()

    try:
        async with async_session() as db:
            # Find sessions without summaries
            logger.info(f"🔍 Searching for sessions with transcripts but no summaries (limit={limit})...")
            sessions = await find_broken_sessions(db, limit)

            if not sessions:
                logger.info("✅ No sessions found without summaries!")
                logger.info("="*80)
                return

            logger.info(f"📋 Found {len(sessions)} sessions without summaries:\n")

            # Display summary table
            print(f"{'ID':>5} | {'Title':45} | {'Status':10} | {'Transcript':10} | {'Created':19}")
            print("-" * 105)

            for s in sessions:
                transcript_len = len(s.transcript.text) if s.transcript else 0
                title = (s.title or "Untitled")[:45]
                created_str = s.created_at.strftime("%Y-%m-%d %H:%M:%S") if s.created_at else "N/A"
                print(f"{s.id:5d} | {title:45} | {s.status.value:10} | {transcript_len:6d} ch | {created_str}")

            print("")

            if dry_run:
                logger.info("🏃 DRY RUN MODE - No changes will be made")
                logger.info("="*80)
                return

            # Confirm before proceeding
            logger.info(f"🚀 Ready to regenerate summaries for {len(sessions)} sessions")

            # Regenerate summaries
            logger.info("")
            logger.info("="*80)
            logger.info("STARTING REGENERATION")
            logger.info("="*80)
            logger.info("")

            success_count = 0
            fail_count = 0

            for idx, session_obj in enumerate(sessions, 1):
                logger.info(f"\n[{idx}/{len(sessions)}] Processing session {session_obj.id}: {session_obj.title}")
                logger.info("-" * 80)

                success = await regenerate_summary_from_transcript(db, session_obj, gemini)

                if success:
                    success_count += 1
                else:
                    fail_count += 1

                # Small delay between API calls to avoid rate limiting
                if idx < len(sessions):
                    logger.info(f"⏸️ Waiting 3 seconds before next session...")
                    await asyncio.sleep(3)

            logger.info("")
            logger.info("="*80)
            logger.info("REGENERATION COMPLETE")
            logger.info("="*80)
            logger.info(f"✅ Successful: {success_count}")
            logger.info(f"❌ Failed: {fail_count}")
            logger.info("="*80)

    finally:
        await engine.dispose()
        logger.info("🔌 Database connection closed")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("\n⚠️ Interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")
        import traceback
        logger.error(traceback.format_exc())
        sys.exit(1)
