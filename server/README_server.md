# Replay FastAPI Server

## Prerequisites
- Python 3.11+
- Poetry or pip

## Setup
```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
cp .env.example .env
alembic upgrade head
uvicorn src.main:app --reload
```

## Tests
```bash
pytest
```
