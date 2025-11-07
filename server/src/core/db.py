from __future__ import annotations

from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _build_engine() -> AsyncEngine:
    settings = get_settings()
    return create_async_engine(
        settings.database_url,
        future=True,
        echo=False,
        pool_pre_ping=False,  # Disabled for performance - adds latency
        pool_size=10,         # Connection pool size
        max_overflow=20,      # Allow burst capacity beyond pool_size
        pool_recycle=3600,    # Recycle connections after 1 hour
        pool_timeout=30,      # Max seconds to wait for connection from pool
    )


engine: AsyncEngine = _build_engine()
async_session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session
