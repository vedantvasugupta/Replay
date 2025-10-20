# Contributing Guide

## Coding Standards
- Use Python 3.11 style type hints throughout the backend. Prefer `pydantic` validation at the edges and keep FastAPI routers thin.
- In Flutter, keep widgets small, prefer Riverpod `StateNotifier` for state, and keep network calls inside repositories in `app/lib/core/`.
- Avoid adding TODO comments in runnable paths. If work is pending, add an item to `TASKS.md`.
- Write focused tests: `pytest` for backend services/routers, `flutter test` for controllers/widgets.
- Run formatters/linters where available (`ruff`, `flutter format`), but the repo ships unopinionated formatting to reduce friction.

## Safe Edit Points (AI & Automation)
- **Backend**
  - Add new endpoints by creating a service in `server/src/services/` and a matching router in `server/src/api/`.
  - Extend data models by updating SQLAlchemy models and the next Alembic migration (never edit old migrations).
  - `GeminiService` contains the integration boundary—swap implementations there without touching routes.
  - Job processing logic in `JobsService.run_worker()` - modify retry logic and backoff strategy here.
  - `TranscriptionService` orchestrates the full pipeline - add checkpointing and partial success handling here.
- **Flutter**
  - Navigation lives in `app/lib/router/app_router.dart`; add routes via `GoRoute` entries.
  - Business logic resides in `app/lib/state/`; prefer new `StateNotifier` classes when expanding features.
  - API contracts mirror backend schemas in `app/lib/domain/`—update these models when the backend changes.
  - Theme customization in `app/lib/core/theme/app_theme.dart` - colors, typography, component styles.
  - Reusable widgets in `app/lib/features/*/widgets/` - keep them stateless and composable.

## Recent Architecture Changes (v2.0)

### Backend Improvements
1. **Combined Gemini API Call**: `GeminiService.transcribe_and_analyze()` replaces separate `transcribe()` + `summarize()` calls
   - Returns structured JSON with transcript, title, summary, action items, timeline, decisions
   - Uses `response_mime_type: "application/json"` for reliable parsing
   - Dynamic timeout calculation based on file size

2. **Retry Logic**: `JobsService.mark_failed()` now supports automatic retries
   - Up to 3 attempts with exponential backoff (2s, 4s, 8s)
   - Detailed error messages include retry count
   - Jobs re-enqueued automatically until max retries

3. **Partial Success Handling**: `TranscriptionService.process_session()` saves progress incrementally
   - Separate transactions for transcript, title, and summary
   - Idempotency checks prevent duplicate processing
   - Session status reflects actual progress (processing/ready/failed)

### Flutter Improvements
1. **Custom Theme System**: `app_theme.dart` defines entire dark mode palette
   - Pure black backgrounds (#000000)
   - Accent colors for status indicators
   - Typography scale with proper letter spacing

2. **Animated Components**: New widget library in `features/home/widgets/`
   - `AnimatedMicButton`: Three-state animation (idle/recording/uploading)
   - `SessionCard`: Glass-morphism cards with status dots

3. **State Management**: Enhanced controllers with better error handling
   - Proper loading states for async operations
   - Error recovery with user-friendly messages

## Before Submitting
1. Ensure `pytest` and `flutter test` pass.
2. Update documentation/ENV samples when adding config.
3. For API changes, document the contract in the relevant README section.
4. Test retry logic manually by simulating failures (disconnect network during upload).
5. Verify UI on different screen sizes (phone, tablet, landscape).
6. Check dark theme consistency across all screens.
