from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.entities import Message, MessageRoleEnum, Session
from .gemini import GeminiService


class ChatService:
    def __init__(self, db: AsyncSession, gemini: GeminiService) -> None:
        self.db = db
        self.gemini = gemini

    async def ask(self, session_id: str, question: str) -> dict:
        result = await self.db.execute(
            select(Session).options(selectinload(Session.transcript)).where(Session.id == session_id)
        )
        session = result.scalar_one_or_none()
        if not session or not session.transcript:
            return {"answer": "Transcript not ready yet.", "citations": []}

        await self._store_message(session_id, MessageRoleEnum.user.value, question)
        answer_payload = await self.gemini.answer(question, session.transcript.text)
        answer = answer_payload.get("answer", "No answer available.")
        citations = answer_payload.get("citations", [])
        await self._store_message(session_id, MessageRoleEnum.assistant.value, answer)
        await self.db.commit()
        return {"answer": answer, "citations": citations}

    async def _store_message(self, session_id: str, role: str, content: str) -> None:
        message = Message(session_id=session_id, role=role, content=content)
        self.db.add(message)
