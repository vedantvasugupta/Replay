.PHONY: dev migrate test lint docker-up docker-down

DEV_ENV?=../server/.env.example

export $(shell sed 's/=.*//' $(DEV_ENV))

dev:
	cd ../server && uvicorn src.app:app --reload --host 0.0.0.0 --port 8000

migrate:
	cd ../server && alembic upgrade head

test:
	cd ../server && pytest

lint:
	cd ../server && ruff check src

docker-up:
	docker compose -f docker-compose.yml up --build

docker-down:
	docker compose -f docker-compose.yml down
