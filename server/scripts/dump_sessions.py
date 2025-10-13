"""
Print a quick snapshot of sessions, transcripts, summaries, and chat messages.

Usage:
    python -m scripts.dump_sessions
"""

from __future__ import annotations

import sqlite3
from pathlib import Path


def _connect_db() -> sqlite3.Connection:
    db_path = Path(__file__).resolve().parent.parent / "replay.db"
    if not db_path.exists():
        raise SystemExit(f"Database not found at {db_path}")
    return sqlite3.connect(db_path)


def main() -> None:
    conn = _connect_db()
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    print("=== Sessions ===")
    for row in cur.execute(
        "SELECT id, user_id, title, status, duration_sec, created_at FROM sessions ORDER BY created_at DESC"
    ):
        print(dict(row))

    print("\n=== Transcripts ===")
    for row in cur.execute(
        "SELECT id, session_id, LENGTH(text) AS text_len, created_at FROM transcripts ORDER BY created_at DESC"
    ):
        print(dict(row))

    print("\n=== Summaries ===")
    for row in cur.execute(
        "SELECT id, session_id, LENGTH(summary) AS summary_len, created_at FROM summaries ORDER BY created_at DESC"
    ):
        print(dict(row))

    print("\n=== Chat Messages ===")
    for row in cur.execute(
        "SELECT id, session_id, role, SUBSTR(content, 1, 80) AS preview, created_at "
        "FROM messages ORDER BY created_at DESC"
    ):
        print(dict(row))

    conn.close()


if __name__ == "__main__":
    main()
