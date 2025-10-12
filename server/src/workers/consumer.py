import asyncio

from ..services.jobs import jobs_service


async def run_worker() -> None:
    await jobs_service.start()
    await jobs_service.queue.join()


if __name__ == "__main__":
    asyncio.run(run_worker())
