from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models.message import Message
from ..models.session import Session
from ..models.enums import MessageRole, SessionStatus
from .gemini_service import GeminiService


class ChatService:
    def __init__(self, gemini: GeminiService) -> None:
        self._gemini = gemini

    async def answer(
        self, db: AsyncSession, session_id: int, user_id: int, user_message: str
    ) -> tuple[Message, Message, list[dict]]:
        stmt = (
            select(Session)
            .where(Session.id == session_id, Session.user_id == user_id)
            .options(selectinload(Session.transcript), selectinload(Session.summary))
        )
        session_obj = await db.scalar(stmt)
        if not session_obj:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
        if session_obj.status != SessionStatus.ready or not session_obj.transcript:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Transcript not ready")

        # Load previous messages for conversation context (last 20 messages)
        messages_stmt = (
            select(Message)
            .where(Message.session_id == session_id)
            .order_by(Message.created_at.desc())
            .limit(20)
        )
        messages_result = await db.scalars(messages_stmt)
        previous_messages = list(reversed(list(messages_result)))  # Reverse to chronological order

        # Build chat history for context
        chat_history = [
            {"role": msg.role.value, "content": msg.content}
            for msg in previous_messages
        ]

        transcript_text = session_obj.transcript.text
        result = await self._gemini.answer(user_message, transcript_text, chat_history)
        answer_text = result.get("answer", "")
        citations = result.get("citations", [])

        user_msg = Message(
            session_id=session_obj.id,
            role=MessageRole.user,
            content=user_message,
            created_at=datetime.now(timezone.utc),
        )
        assistant_msg = Message(
            session_id=session_obj.id,
            role=MessageRole.assistant,
            content=answer_text,
            created_at=datetime.now(timezone.utc),
        )
        db.add_all([user_msg, assistant_msg])
        await db.commit()
        await db.refresh(user_msg)
        await db.refresh(assistant_msg)
        return user_msg, assistant_msg, citations
