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
    speaker: str
    text: str
    start_time: str


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
