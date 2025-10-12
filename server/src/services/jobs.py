import asyncio

from ..core.database import AsyncSessionLocal
from .gemini import GeminiService
from .transcription import TranscriptionService


class JobsService:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self._worker_started = False

    async def enqueue_transcription(self, session_id: str) -> None:
        await self.queue.put(session_id)

    async def start(self) -> None:
        if not self._worker_started:
            asyncio.create_task(self._worker())
            self._worker_started = True

    async def _worker(self) -> None:
        gemini = GeminiService()
        while True:
            session_id = await self.queue.get()
            async with AsyncSessionLocal() as session:
                service = TranscriptionService(session, gemini)
                await service.process_session(session_id)
            self.queue.task_done()


jobs_service = JobsService()
