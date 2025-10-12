.PHONY: dev down server tests flutter

dev:
cd infra && docker-compose up --build

down:
cd infra && docker-compose down

server:
cd server && uvicorn src.main:app --reload

server-tests:
cd server && pytest

flutter:
cd app && flutter run --flavor dev -t lib/main_dev.dart
