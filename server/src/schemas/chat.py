from __future__ import annotations

from pydantic import Field

from .base import CamelModel


class ChatMessageRequest(CamelModel):
    message: str = Field(min_length=1, max_length=2000)


class Citation(CamelModel):
    timestamp: float
    quote: str


class ChatMessageResponse(CamelModel):
    assistant_message: str
    citations: list[Citation]
