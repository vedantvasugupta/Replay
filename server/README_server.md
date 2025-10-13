# Replay FastAPI Backend

## Requirements
- Python 3.11+
- [Poetry](https://python-poetry.org/) optional, commands below use `pip`

## Setup
```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
```

Edit `.env` to set `JWT_SECRET`, `GEMINI_*` values, and any other overrides. The default configuration uses SQLite and local media storage under `./media`.

For a Railway deploy that keeps using SQLite and filesystem storage:
- Attach a Persistent Volume (e.g. mounted at `/mnt/data`).
- Set `DATABASE_URL=sqlite+aiosqlite:///mnt/data/db/replay.db` and `MEDIA_ROOT=/mnt/data/media` through Railway variables.
- Provide the other secrets (`JWT_SECRET`, `GEMINI_*`, etc.) the same way.
- Deploy with `railway up` (Procfile already runs `uvicorn`).
- Run `railway shell` followed by `alembic upgrade head` to apply migrations.

For a Railway deploy using the managed Postgres add-on:
- Run `railway variables -s postgres -k` to copy the generated `DATABASE_URL`.
- Convert it to async notation: `postgresql+asyncpg://USER:PASSWORD@HOST:PORT/DB`.
- Set that on the FastAPI service: `railway variables --set "DATABASE_URL=postgresql+asyncpg://..."`.
- Deploy with `railway up -s <service>` and, once live, execute migrations via `python3 -m alembic upgrade head` in `railway ssh`.

## Database
Run migrations (creates tables in `replay.db`):
```bash
alembic upgrade head
```

## Running the API
```bash
uvicorn src.app:app --reload --host 0.0.0.0 --port 8000
```

The API documentation is available at `http://127.0.0.1:8000/docs`.

## Tests
```bash
pytest
```

## Switching to Postgres or S3
- **Database**: set `DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/dbname` and provide credentials. Re-run Alembic migrations.
- **Storage**: implement a new service conforming to `StorageService` in `src/services/storage_service.py` (e.g. `S3StorageService`). Update `StorageSettings.provider` to select the implementation.

## Background Processing
A lightweight in-process jobs queue pushes transcription work onto an async worker created at startup. For hosted environments, replace `JobsService` with an adapter to your task runner, keeping the `enqueue_transcription` interface stable.
