# Infrastructure

## Docker Compose
Spin up the FastAPI backend in a container (SQLite + local storage) with live reload:

```bash
cd infra
docker compose up --build
```

The container mounts the local `server/` directory for rapid iteration and serves the API on `http://localhost:8000`.

## Make Targets
All commands are executed from the `infra/` directory.

- `make dev` – start the FastAPI server locally with auto-reload.
- `make migrate` – apply database migrations.
- `make test` – run backend pytest suite.
- `make docker-up` / `make docker-down` – manage the Docker Compose stack.
