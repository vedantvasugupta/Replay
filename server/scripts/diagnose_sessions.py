"""
Diagnose session processing issues.

This script checks:
1. Sessions with transcripts but no summaries
2. Sessions stuck in processing status
3. Recent failed jobs
4. Chat message counts per session

Usage:
    python -m scripts.diagnose_sessions
"""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, selectinload

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models.session import Session
from src.models.transcript import Transcript
from src.models.summary import Summary
from src.models.job import Job
from src.models.message import Message
from src.models.enums import SessionStatus
from src.core.config import get_settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)


async def diagnose(db: AsyncSession):
    """Run diagnostics on the database."""

    print("\n" + "="*80)
    print("SESSION DIAGNOSTICS REPORT")
    print("="*80 + "\n")

    # 1. Overall session stats
    print("📊 OVERALL STATISTICS")
    print("-" * 80)

    total_sessions = await db.scalar(select(func.count(Session.id)))
    print(f"Total sessions: {total_sessions}")

    sessions_by_status = await db.execute(
        select(Session.status, func.count(Session.id))
        .group_by(Session.status)
    )
    print("\nSessions by status:")
    for status, count in sessions_by_status:
        print(f"  {status.value:12s}: {count}")

    # 2. Sessions with transcripts but no summaries
    print("\n\n🚨 SESSIONS WITH TRANSCRIPTS BUT NO SUMMARIES")
    print("-" * 80)

    stmt = (
        select(Session)
        .outerjoin(Transcript, Session.id == Transcript.session_id)
        .outerjoin(Summary, Session.id == Summary.session_id)
        .where(Transcript.id.isnot(None))
        .where(Summary.id.is_(None))
        .order_by(Session.created_at.desc())
        .limit(15)
        .options(
            selectinload(Session.transcript),
            selectinload(Session.summary)
        )
    )

    result = await db.execute(stmt)
    sessions_no_summary = result.scalars().all()

    if sessions_no_summary:
        print(f"Found {len(sessions_no_summary)} sessions with transcripts but no summaries:\n")
        for s in sessions_no_summary:
            transcript_len = len(s.transcript.text) if s.transcript else 0
            print(f"  Session {s.id:3d}: {s.title[:45]:45s} | Status: {s.status.value:10s} | Transcript: {transcript_len:6d} chars | Created: {s.created_at}")
    else:
        print("✅ All sessions with transcripts have summaries!")

    # 3. Sessions stuck in processing
    print("\n\n⏳ SESSIONS STUCK IN PROCESSING")
    print("-" * 80)

    stmt = (
        select(Session)
        .where(Session.status == SessionStatus.processing)
        .order_by(Session.created_at.desc())
        .limit(10)
        .options(
            selectinload(Session.transcript),
            selectinload(Session.summary)
        )
    )

    result = await db.execute(stmt)
    processing_sessions = result.scalars().all()

    if processing_sessions:
        print(f"Found {len(processing_sessions)} sessions stuck in processing:\n")
        for s in processing_sessions:
            has_transcript = "✅" if s.transcript else "❌"
            has_summary = "✅" if s.summary else "❌"
            print(f"  Session {s.id:3d}: {s.title[:40]:40s} | Transcript: {has_transcript} | Summary: {has_summary} | Created: {s.created_at}")
    else:
        print("✅ No sessions stuck in processing!")

    # 4. Failed jobs
    print("\n\n❌ RECENT FAILED JOBS")
    print("-" * 80)

    stmt = (
        select(Job)
        .where(Job.status == "failed")
        .order_by(Job.updated_at.desc())
        .limit(10)
    )

    result = await db.execute(stmt)
    failed_jobs = result.scalars().all()

    if failed_jobs:
        print(f"Found {len(failed_jobs)} recent failed jobs:\n")
        for job in failed_jobs:
            error_preview = (job.error_message or "")[:60]
            print(f"  Job {job.id:3d}: Session {job.session_id:3d} | Attempts: {job.attempts} | Error: {error_preview}")
    else:
        print("✅ No failed jobs!")

    # 5. Recent sessions with details
    print("\n\n📋 LAST 15 SESSIONS (DETAILED VIEW)")
    print("-" * 80)

    stmt = (
        select(Session)
        .order_by(Session.created_at.desc())
        .limit(15)
        .options(
            selectinload(Session.transcript),
            selectinload(Session.summary)
        )
    )

    result = await db.execute(stmt)
    recent_sessions = result.scalars().all()

    print(f"{'ID':>3} | {'Title':40} | {'Status':10} | {'T':1} | {'S':1} | {'Chat':4} | {'Created':19}")
    print("-" * 95)

    for s in recent_sessions:
        has_transcript = "✓" if s.transcript else "✗"
        has_summary = "✓" if s.summary else "✗"

        # Count chat messages
        msg_count_stmt = select(func.count(Message.id)).where(Message.session_id == s.id)
        msg_count = await db.scalar(msg_count_stmt)

        title = (s.title or "Untitled")[:40]
        created_str = s.created_at.strftime("%Y-%m-%d %H:%M:%S") if s.created_at else "N/A"

        print(f"{s.id:3d} | {title:40} | {s.status.value:10} | {has_transcript} | {has_summary} | {msg_count:4d} | {created_str}")

    # 6. Chat issues - sessions with messages but status != ready
    print("\n\n💬 CHAT ISSUES - Messages on Non-Ready Sessions")
    print("-" * 80)

    stmt = (
        select(Session)
        .join(Message, Session.id == Message.session_id)
        .where(Session.status != SessionStatus.ready)
        .distinct()
        .options(selectinload(Session.transcript), selectinload(Session.summary))
    )

    result = await db.execute(stmt)
    chat_issue_sessions = result.scalars().all()

    if chat_issue_sessions:
        print(f"Found {len(chat_issue_sessions)} sessions with chat messages but not in 'ready' status:\n")
        for s in chat_issue_sessions:
            msg_count_stmt = select(func.count(Message.id)).where(Message.session_id == s.id)
            msg_count = await db.scalar(msg_count_stmt)
            print(f"  Session {s.id:3d}: {s.title[:40]:40s} | Status: {s.status.value:10s} | Messages: {msg_count}")
    else:
        print("✅ No chat issues detected!")

    print("\n" + "="*80)
    print("DIAGNOSTICS COMPLETE")
    print("="*80 + "\n")


async def main():
    """Main entry point."""
    logger.info("🚀 Starting session diagnostics...")

    # Get database URL from settings
    settings = get_settings()
    database_url = settings.database_url

    # Convert postgres:// to postgresql+asyncpg://
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+asyncpg://", 1)
    elif database_url.startswith("sqlite"):
        if not database_url.startswith("sqlite+aiosqlite"):
            database_url = database_url.replace("sqlite://", "sqlite+aiosqlite://", 1)

    engine = create_async_engine(database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as db:
        await diagnose(db)

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
