from __future__ import annotations

import asyncio
import os
import pathlib
import shutil
from typing import AsyncIterator

import pytest
import pytest_asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

TEST_DB = pathlib.Path("./test_replay.db")
TEST_MEDIA_ROOT = pathlib.Path("./test_media")

os.environ.setdefault("DATABASE_URL", f"sqlite+aiosqlite:///{TEST_DB}")
os.environ.setdefault("JWT_SECRET", "test-secret")
os.environ.setdefault("ACCESS_EXPIRES_MIN", "15")
os.environ.setdefault("REFRESH_EXPIRES_DAYS", "7")
os.environ.setdefault("MEDIA_ROOT", str(TEST_MEDIA_ROOT))
os.environ.setdefault("GEMINI_PROJECT", "test-project")
os.environ.setdefault("GEMINI_LOCATION", "us-central1")
os.environ.setdefault("GEMINI_MODEL", "gemini-2.5-pro")
os.environ.setdefault("BACKGROUND_POLL_INTERVAL", "0")

from src.app import app  # noqa: E402
from src.core.config import get_settings  # noqa: E402
from src.core.db import Base  # noqa: E402


@pytest.fixture(scope="session")
def event_loop() -> asyncio.AbstractEventLoop:
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session")
async def migrated_engine() -> AsyncIterator[AsyncEngine]:
    get_settings.cache_clear()
    engine = create_async_engine(get_settings().database_url, future=True)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()
    if TEST_DB.exists():
        TEST_DB.unlink()
    if TEST_MEDIA_ROOT.exists():
        shutil.rmtree(TEST_MEDIA_ROOT)


@pytest_asyncio.fixture
async def async_client(migrated_engine: AsyncEngine) -> AsyncIterator[AsyncClient]:  # noqa: ARG001
    async with AsyncClient(app=app, base_url="http://testserver") as client:
        yield client
