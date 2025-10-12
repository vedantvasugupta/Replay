import asyncio
import os
from importlib import reload

import pytest
from httpx import AsyncClient

from src.main import app
from src.core import config as config_module
from src.models.base import Base


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session", autouse=True)
async def setup_database():
    os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test.db"
    config_module.get_settings.cache_clear()
    from src.core import database as database_module

    reload(database_module)
    async with database_module._engine.begin() as conn:  # type: ignore[attr-defined]
        await conn.run_sync(Base.metadata.create_all)
    yield
    await database_module._engine.dispose()  # type: ignore[attr-defined]
    if os.path.exists("test.db"):
        os.remove("test.db")


@pytest.fixture
async def client():
    async with AsyncClient(app=app, base_url="http://test") as async_client:
        yield async_client
