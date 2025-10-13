"""Add OAuth fields to users

Revision ID: 0002_add_oauth_fields
Revises: 0001_initial
Create Date: 2025-10-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0002_add_oauth_fields"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add new columns for OAuth support
    op.add_column("users", sa.Column("provider", sa.String(length=50), nullable=False, server_default="email"))
    op.add_column("users", sa.Column("google_id", sa.String(length=255), nullable=True))

    # SQLite doesn't support ALTER COLUMN, so we skip making password_hash nullable
    # The model already allows NULL, so new OAuth users will work fine
    # Existing users will keep their non-null password hashes

    # Add index for google_id
    op.create_index(op.f("ix_users_google_id"), "users", ["google_id"], unique=True)


def downgrade() -> None:
    op.drop_index(op.f("ix_users_google_id"), table_name="users")
    # Skip reverting password_hash nullable change (see upgrade() comment)
    op.drop_column("users", "google_id")
    op.drop_column("users", "provider")
