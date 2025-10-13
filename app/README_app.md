# Replay Flutter Client

## Prerequisites
- Flutter 3.19+ with stable channel
- Android Studio / SDK tools for device or emulator

## Environment
1. Copy `assets/env/.env.example` to `assets/env/.env` and adjust `API_BASE_URL` to point to the FastAPI backend (e.g. `http://192.168.1.10:8000`).
2. Ensure the backend is running and reachable from the Android device (use LAN IP or tunnel).

## Setup
```bash
cd app
flutter pub get
flutter create .   # generates missing android/ios folders if absent
```

If you already have platform folders, skip the `flutter create` step.

## Running
```bash
flutter run -d android
```

## Tests
```bash
flutter test
```

## Notes
- Recording uses the [`record`](https://pub.dev/packages/record) plugin; Android will prompt for microphone permission on first use.
- Pending uploads are retried on app launch or via the _Retry Pending Uploads_ button on the record screen.
