# Infra

## Docker
- `Dockerfile.server` builds the FastAPI app.
- `docker-compose.yml` starts the API and a SQLite volume (in dev) alongside optional MinIO stub.

## Make targets
- `make dev` – run docker-compose in development mode.
- `make down` – stop running services.
