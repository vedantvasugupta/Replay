from __future__ import annotations

import asyncio
from typing import Any

from ..core.config import get_settings


class GeminiService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def transcribe(self, audio_path: str) -> dict[str, Any]:
        if not self.settings.gemini_project:
            return {
                "text": "This is a placeholder transcript.",
                "segments": [
                    {"text": "This is a placeholder transcript.", "speaker": "Speaker", "start": "0:00"}
                ],
            }
        await asyncio.sleep(0.1)
        return {
            "text": "Gemini transcription not implemented in local mode.",
            "segments": [],
        }

    async def summarize(self, transcript: str) -> dict[str, Any]:
        if not self.settings.gemini_project:
            return {
                "summary": transcript[:200],
                "action_items": ["Review notes"],
                "timeline": ["00:00 Kickoff"],
                "decisions": ["Proceed with MVP"],
            }
        await asyncio.sleep(0.1)
        return {
            "summary": "Gemini summary not implemented in local mode.",
            "action_items": [],
            "timeline": [],
            "decisions": [],
        }

    async def answer(self, question: str, transcript: str) -> dict[str, Any]:
        if not self.settings.gemini_project:
            snippet = transcript[:160] or "No transcript available yet."
            return {
                "answer": f"Based on the transcript: {snippet}",
                "citations": [
                    {
                        "t": "00:00",
                        "quote": snippet,
                    }
                ],
            }
        await asyncio.sleep(0.1)
        return {
            "answer": "Gemini chat not implemented in local mode.",
            "citations": [],
        }
