from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, Interval, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import Base
from .enums import SessionStatus


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    audio_asset_id: Mapped[int] = mapped_column(ForeignKey("audio_assets.id", ondelete="SET NULL"), nullable=True)
    status: Mapped[SessionStatus] = mapped_column(Enum(SessionStatus), default=SessionStatus.uploaded, nullable=False)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )

    user: Mapped["User"] = relationship("User", back_populates="sessions")
    audio_asset: Mapped["AudioAsset"] = relationship("AudioAsset", back_populates="session")
    transcript: Mapped["Transcript"] = relationship(
        "Transcript", back_populates="session", cascade="all, delete-orphan", uselist=False
    )
    summary: Mapped["Summary"] = relationship(
        "Summary", back_populates="session", cascade="all, delete-orphan", uselist=False
    )
    messages: Mapped[list["Message"]] = relationship(
        "Message", back_populates="session", cascade="all, delete-orphan", order_by="Message.created_at"
    )
