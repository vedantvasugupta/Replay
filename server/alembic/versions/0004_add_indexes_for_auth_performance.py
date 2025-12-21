"""Add indexes for auth performance

Revision ID: 0004_add_auth_indexes
Revises: 0003_add_speakers_to_transcripts
Create Date: 2025-11-07
"""

from __future__ import annotations

from alembic import op


revision = "0004_add_auth_indexes"
down_revision = "0003_add_speakers_to_transcripts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add indexes on User table for faster authentication queries
    # Index on email for login and registration lookups
    op.create_index(
        "idx_users_email",
        "users",
        ["email"],
        unique=False
    )

    # Index on google_id for Google OAuth lookups
    op.create_index(
        "idx_users_google_id",
        "users",
        ["google_id"],
        unique=False
    )


def downgrade() -> None:
    op.drop_index("idx_users_google_id", table_name="users")
    op.drop_index("idx_users_email", table_name="users")
