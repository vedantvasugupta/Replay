# Contributing to Replay

## Coding standards
- Keep modules short and focused. New features should land in their own files under `app/lib/` or `server/src/`.
- Prefer pure functions and explicit types.
- Do not place business logic inside FastAPI routers or Flutter widgets; call into services/providers instead.
- Run `pytest` for the server and `flutter test` for the app before committing.

## Safe edit points for AI tools
- Flutter: add screens under `app/lib/features/`, new providers in `app/lib/providers/`, networking helpers in `app/lib/core/`.
- Backend: add routes inside `server/src/api/`, services under `server/src/services/`, schemas under `server/src/schemas/`.
- Jobs: extend queue logic in `server/src/services/jobs.py`.
- Storage: swap implementations by creating a class that implements `StorageService` in `server/src/services/storage.py` and updating `get_storage_service`.

## Workflow
1. Create a feature branch.
2. Update or add tests.
3. Ensure documentation and `.env.example` reflect new configuration keys.
4. Submit a PR with a clear summary and testing evidence.
