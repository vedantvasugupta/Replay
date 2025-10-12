# Replay Flutter App

## Prerequisites
- Flutter 3.22+ with Android toolchain
- Android Studio (for emulators) or a physical Android device

## Environment configuration
Copy `.env.example` to `.env` and adjust the `API_BASE_URL` to the LAN IP where the backend is reachable.

```bash
cd app
cp .env.example .env
```

## Run the app

```bash
flutter create . --platforms=android
flutter pub get
flutter run --flavor dev -t lib/main_dev.dart
```

## Tests

```bash
flutter test
```
