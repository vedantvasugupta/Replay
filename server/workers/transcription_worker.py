from __future__ import annotations

import asyncio

from src.app import get_app_state
from src.core.db import async_session_factory


async def main() -> None:
    state = get_app_state()

    async def handler(session, job):
        await state.transcription_service.process_session(session, job.session_id)

    await state.jobs_service.run_worker(async_session_factory, handler)


if __name__ == "__main__":
    asyncio.run(main())
