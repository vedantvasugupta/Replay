"""Add speakers to transcripts

Revision ID: 0003_add_speakers_to_transcripts
Revises: 0002_add_oauth_fields
Create Date: 2025-10-22
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0003_add_speakers_to_transcripts"
down_revision = "0002_add_oauth_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add speakers_json column for speaker diarization data
    op.add_column("transcripts", sa.Column("speakers_json", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("transcripts", "speakers_json")
