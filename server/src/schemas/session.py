from __future__ import annotations

from datetime import datetime

from ..models.enums import MessageRole, SessionStatus
from .base import CamelModel


class SessionListItem(CamelModel):
    id: int
    status: SessionStatus
    duration_sec: int | None
    title: str | None
    created_at: datetime


class TranscriptSegment(CamelModel):
    # Support both old format (start/end) and new format (speaker/start_time)
    text: str
    speaker: str | None = None
    start_time: str | None = None
    start: float | None = None
    end: float | None = None


class TranscriptRead(CamelModel):
    text: str
    segments: list[TranscriptSegment]


class SummaryRead(CamelModel):
    summary: str
    action_items: list[str]
    timeline: list[str]
    decisions: list[str]


class SessionMeta(CamelModel):
    id: int
    status: SessionStatus
    duration_sec: int | None
    title: str | None
    created_at: datetime


class SessionDetail(CamelModel):
    meta: SessionMeta
    transcript: TranscriptRead | None = None
    summary: SummaryRead | None = None


class MessageRead(CamelModel):
    id: int
    role: MessageRole
    content: str
    created_at: datetime


class UpdateSessionTitleRequest(CamelModel):
    title: str
