from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, ConfigDict


class SessionSummarySchema(BaseModel):
    id: str
    createdAt: datetime = Field(alias="created_at")
    status: str
    durationSec: Optional[int] = Field(default=None, alias="duration_sec")

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)


class SessionListResponse(BaseModel):
    __root__: List[SessionSummarySchema]


class TranscriptSegment(BaseModel):
    text: str
    speaker: Optional[str] = None
    start: Optional[str] = None


class SummaryInsights(BaseModel):
    summary: str
    action_items: List[str] = Field(default_factory=list)
    timeline: List[str] = Field(default_factory=list)
    decisions: List[str] = Field(default_factory=list)


class SessionDetailResponse(BaseModel):
    meta: SessionSummarySchema
    transcript: Optional[str] = None
    segments: Optional[List[TranscriptSegment]] = None
    summary: Optional[SummaryInsights] = None


class IngestRequest(BaseModel):
    assetId: str = Field(alias="assetId")


class ChatRequest(BaseModel):
    message: str


class ChatCitation(BaseModel):
    t: str
    quote: str


class ChatResponse(BaseModel):
    role: str = "assistant"
    content: str
    citations: List[ChatCitation] = Field(default_factory=list)
