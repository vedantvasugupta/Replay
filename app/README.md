# Replay App

Flutter mobile client for the Replay meeting note-taker application.

## Prerequisites

- Flutter SDK (>=3.3.0 <4.0.0)
- Android Studio / Xcode (for mobile development)
- A running instance of the Replay server backend

## Getting Started

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd app
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Environment

Create a `.env` file in `assets/env/`:

```bash
cp assets/env/.env.example assets/env/.env
```

Edit `assets/env/.env` and set your API base URL:

```
API_BASE_URL=http://your-server-url:8000
```

For local development, use `http://10.0.2.2:8000` for Android emulator or `http://127.0.0.1:8000` for iOS simulator.

### 4. Run the App

```bash
flutter run
```

## Project Structure

```
lib/
├── core/           # Core functionality (API, auth, services)
├── domain/         # Domain models
├── features/       # Feature modules (auth, home, recording, etc.)
├── router/         # Navigation configuration
└── state/          # State management (Riverpod controllers)
```

## Platform-Specific Setup

### Android

- Google Services configuration is included
- Minimum SDK: Check `android/app/build.gradle.kts`

### iOS

- Ensure proper code signing in Xcode
- Update `Info.plist` for required permissions (microphone, etc.)

## Development

Run tests:
```bash
flutter test
```

Build for release:
```bash
flutter build apk  # Android
flutter build ios  # iOS
```

## Features

- Google OAuth authentication
- Audio recording and session management
- Real-time transcription
- Session playback and chat
- File upload support

## Troubleshooting

- If you get environment errors, ensure `.env` file exists in `assets/env/`
- For Android build issues, try `flutter clean && flutter pub get`
- For recording issues on Linux, check the `third_party/record_linux` plugin
