# Replay – AI-Powered Meeting Note-Taker

Replay captures meeting audio on Android, ships it to a FastAPI backend for transcription via Gemini, and presents AI-generated summaries, smart titles, and chat Q&A in a modern dark-mode Flutter client.

## Repository Layout
- `app/` – Flutter mobile client (Material 3, Riverpod, dark theme, animated UI)
- `server/` – FastAPI backend with SQLite + SQLAlchemy + Alembic
- `infra/` – Docker compose, Makefile, and infra helpers
- `.github/workflows/` – CI for backend + Flutter tests

## Key Features
✨ **Modern Dark UI** – Pure black theme with animated mic button and glass-morphism cards
🎯 **Smart Titles** – AI-generated descriptive titles from transcript content
📊 **Rich Summaries** – Action items, timeline, and decisions automatically extracted
💬 **Chat Q&A** – Ask questions about your recordings with AI-powered answers
🔄 **Reliable Processing** – 3x automatic retries with exponential backoff
⚡ **Optimized API** – Single Gemini call for transcription + summary + title (50% cost reduction)
📝 **Editable Titles** – Click-to-edit session titles with inline editing
💾 **Partial Success** – Transcript saved even if summary generation fails
📤 **Audio Upload** – Upload existing audio files (MP3, M4A, WAV, etc.) for transcription

## Quick Start
### Backend
```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
alembic upgrade head
uvicorn src.app:app --reload --host 0.0.0.0 --port 8000
```

The API listens on `http://127.0.0.1:8000`. Media is stored under `server/media/`.

### Flutter Client
```bash
cd app
flutter pub get
flutter create .    # generates android/ios folders if missing
cp assets/env/.env.example assets/env/.env
flutter run -d android
```
Set `API_BASE_URL` inside `.env` to the LAN IP of the backend when running on a physical device.

### Make Targets & Docker
```bash
cd infra
make dev            # run backend locally with reload
make migrate        # apply Alembic migrations
make docker-up      # containerised backend
```

## Testing
- Backend: `cd server && pytest`
- Flutter: `cd app && flutter test`

CI runs both suites on every push/PR.

## Deployment

### Railway Deployment
The backend is deployed on Railway for production hosting:

```bash
cd server
railway up
```

This command deploys the FastAPI backend to Railway. Ensure you have:
- Railway CLI installed (`npm i -g @railway/cli`)
- Railway account linked (`railway login`)
- Environment variables configured in Railway dashboard (API keys, database URL, etc.)

### Moving to Other Cloud Providers
- Swap SQLite for Postgres by updating `DATABASE_URL` (see `README_server.md`), then rerun Alembic migrations.
- Replace the storage implementation by adding an S3/GCS adapter that matches `StorageService` and toggling `STORAGE_PROVIDER`.
- Gemini credentials live in environment variables; production deployments should inject them via secret managers.
- The background jobs layer (`JobsService`) can be wired to Cloud Tasks or Pub/Sub while keeping the enqueue interface intact.

## Recent Enhancements (v2.0)

### UI/UX Improvements
- **Complete Dark Mode Redesign**: Pure black (#000000) theme with custom color palette
- **Animated Mic Button**: Breathing effect (idle), pulsing red rings (recording), rotating (uploading)
- **Modern Home Screen**: Centered recording UI with bottom recordings section (no overflow issues)
- **Session Cards**: Glass-morphism styling with glowing status indicators
- **Enhanced Detail Screens**: Icon-based tabs, card layouts for summaries, modern chat bubbles
- **Inline Title Editing**: Click-to-edit session titles directly in the app bar
- **Audio File Upload**: Upload existing audio files from device storage (supports 10+ formats: MP3, M4A, WAV, AAC, OPUS, OGG, FLAC, WMA, AIFF, WEBM)

### Backend Optimizations
- **Combined API Call**: Single Gemini request for transcription + summary + title (2 calls → 1 call)
- **Smart Retry Logic**: Up to 3 automatic retries with exponential backoff (2s, 4s, 8s)
- **Dynamic Timeouts**: Scales with file size (120s base + 1s per 50KB)
- **Partial Success Handling**: Saves transcript even if summary fails (separate transactions)
- **Idempotency**: Safe to rerun jobs without duplicating data
- **Better Error Messages**: Detailed logging with exact error types and stack traces
- **AI Title Generation**: Automatic descriptive titles from transcript analysis

### Reliability Improvements
- **Job Recovery**: Failed jobs automatically retry instead of permanent failure
- **Session Status Management**: Proper state tracking (processing → ready/failed)
- **Graceful Degradation**: App remains functional even with partial data
- **Error Recovery**: Built-in handling for API timeouts, rate limits, and network issues

## Architecture Notes

### Backend Services (`server/src/services/`)
- `GeminiService`: Combined transcription/analysis with JSON-mode responses
- `TranscriptionService`: Orchestrates processing with partial success handling
- `JobsService`: Background job queue with retry logic and exponential backoff
- `SessionService`: Session CRUD + title updates
- `ChatService`: Q&A with transcript context

### Flutter Architecture (`app/lib/`)
- **Theme**: `core/theme/app_theme.dart` - Custom dark Material 3 theme
- **Widgets**: `features/home/widgets/` - Animated mic button, session cards
- **State**: Riverpod `StateNotifier` controllers for recordings and sessions
- **UI**: Responsive layouts with proper constraint handling

## AI-Friendly Editing
- Backend services live in `server/src/services/` with narrow, typed interfaces.
- Pydantic schemas reside in `server/src/schemas/`; update them when extending the API.
- Flutter state controllers are under `app/lib/state/` and consume repositories/services from `app/lib/core/`.
- `TASKS.md` enumerates incremental enhancements safe for follow-up automation.
