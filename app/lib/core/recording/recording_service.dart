import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class RecordingResult {
  RecordingResult({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;
}

abstract class IRecordingService {
  Future<bool> canRecord();
  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  Future<RecordingResult?> stop();
  Future<void> cancel();
}

class RecordingService implements IRecordingService {
  RecordingService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  DateTime? _startedAt;

  @override
  Future<bool> canRecord() async {
    if (kIsWeb) {
      return false;
    }

    // Check microphone permission
    final hasAudioPermission = await _recorder.hasPermission();
    if (!hasAudioPermission) {
      return false;
    }

    // Check and request storage permission on Android
    if (!kIsWeb && Platform.isAndroid) {
      final hasStoragePermission = await _checkAndRequestStoragePermission();
      if (!hasStoragePermission) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _checkAndRequestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true; // No storage permission needed for iOS/other platforms
    }

    // Check Android version
    final sdkInt = await _getAndroidSdkVersion();

    // Android 10+ (API 29+): No storage permission needed when using MediaStore
    // Android < 10: Need WRITE_EXTERNAL_STORAGE permission
    if (sdkInt >= 29) {
      return true; // No permission needed for MediaStore on Android 10+
    }

    // For Android < 10, request storage permission
    final permission = Permission.storage;
    final status = await permission.status;

    if (status.isGranted) {
      return true;
    }

    final result = await permission.request();

    if (result.isGranted) {
      return true;
    }

    if (result.isPermanentlyDenied) {
      print('[RecordingService] Storage permission permanently denied. Please enable it in Settings.');
    }

    return false;
  }

  Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      print('[RecordingService] Failed to detect Android version: $e');
      return 29; // Default to Android 10 (safer default)
    }
  }

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  RecordConfig _recordConfig() {
    if (_isWindows) {
      return const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 2,
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      return const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        audioInterruption: AudioInterruptionMode.none,
      );
    }
    return const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );
  }

  String get _fileExtension => _isWindows ? 'wav' : 'm4a';

  Future<String> _nextFilePath() async {
    final now = DateTime.now();
    Directory baseDir;

    if (!kIsWeb && Platform.isAndroid) {
      // For all Android versions, use public Music directory
      // Path: /storage/emulated/0/Music/Replay/
      // Benefits:
      // - Accessible via any file manager app
      // - Files persist after app uninstall
      // - No special permissions needed on Android 10+ for app-created files
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null && externalDir.path.contains('Android/data')) {
        // Convert from app-specific path to public Music path
        // e.g., /storage/emulated/0/Android/data/replay.app/files
        //    -> /storage/emulated/0/Music/Replay
        final parts = externalDir.path.split('/');
        final androidIndex = parts.indexOf('Android');
        if (androidIndex > 0) {
          final publicPath = parts.sublist(0, androidIndex).join('/');
          baseDir = Directory(p.join(publicPath, 'Music', 'Replay'));
        } else {
          baseDir = Directory(p.join(externalDir.path, 'Music', 'Replay'));
        }
      } else if (externalDir != null) {
        baseDir = Directory(p.join(externalDir.path, 'Music', 'Replay'));
      } else {
        // Fallback to Downloads folder if external storage unavailable
        baseDir = Directory('/storage/emulated/0/Download/Replay');
        print('[RecordingService] Using fallback Downloads directory');
      }
    } else if (!kIsWeb && Platform.isIOS) {
      // On iOS, save to documents directory (accessible via Files app)
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      // Windows, macOS, Linux - use documents directory
      baseDir = await getApplicationDocumentsDirectory();
    }

    // Create a single recordings folder (no date-based subfolders)
    final recordingsDir = Directory(p.join(baseDir.path, 'recordings'));

    try {
      if (!recordingsDir.existsSync()) {
        recordingsDir.createSync(recursive: true);
        print('[RecordingService] Created recordings directory: ${recordingsDir.path}');
      }
    } catch (e) {
      print('[RecordingService] Failed to create directory at ${recordingsDir.path}: $e');
      // Fallback to app documents directory
      final fallbackDir = await getApplicationDocumentsDirectory();
      final fallbackRecordingsDir = Directory(p.join(fallbackDir.path, 'recordings'));
      if (!fallbackRecordingsDir.existsSync()) {
        fallbackRecordingsDir.createSync(recursive: true);
      }
      print('[RecordingService] Using fallback directory: ${fallbackRecordingsDir.path}');

      final dateTime = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final filename = '$dateTime.$_fileExtension';
      return p.join(fallbackRecordingsDir.path, filename);
    }

    // Create a filename with date and time: 2025-01-22_14-30-45.m4a
    final dateTime = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final filename = '$dateTime.$_fileExtension';

    final filePath = p.join(recordingsDir.path, filename);
    print('[RecordingService] Saving recording to: $filePath');

    return filePath;
  }

  @override
  Future<void> start() async {
    if (kIsWeb) {
      throw UnsupportedError('Recording is not supported on the web client.');
    }
    final path = await _nextFilePath();
    _startedAt = DateTime.now();
    await _recorder.start(
      _recordConfig(),
      path: path,
    );
  }

  @override
  Future<void> pause() async {
    await _recorder.pause();
  }

  @override
  Future<void> resume() async {
    await _recorder.resume();
  }

  @override
  Future<RecordingResult?> stop() async {
    final filePath = await _recorder.stop();
    if (filePath == null) {
      return null;
    }
    final started = _startedAt ?? DateTime.now();
    final duration = DateTime.now().difference(started);
    _startedAt = null;
    return RecordingResult(filePath: filePath, duration: duration);
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    _startedAt = null;
  }
}
