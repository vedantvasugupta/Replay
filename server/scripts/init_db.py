"""Initialize the database by creating all tables."""
import asyncio
from src.core.db import engine, Base

async def init_db():
    """Create all tables in the database."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("Database tables created successfully!")

if __name__ == "__main__":
    asyncio.run(init_db())
