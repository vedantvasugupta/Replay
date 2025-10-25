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
      final sdkInt = await _getAndroidSdkVersion();

      if (sdkInt >= 29) {
        // Android 10+ (API 29+): Use app-specific external storage
        // Path: /storage/emulated/0/Android/data/replay.app/files/Music/Replay/
        // Benefits:
        // - No permissions required
        // - Accessible via file managers (under app's folder)
        // - Works with scoped storage
        // Note: Files are deleted when app is uninstalled
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          // Use Music subfolder for better organization
          baseDir = Directory(p.join(externalDir.path, 'Music', 'Replay'));
        } else {
          baseDir = await getApplicationDocumentsDirectory();
        }
      } else {
        // Android < 10: Use public Music directory
        // Path: /storage/emulated/0/Music/Replay/
        // Requires WRITE_EXTERNAL_STORAGE permission (already requested)
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final parts = externalDir.path.split('/');
          final publicPath = parts.sublist(0, parts.indexOf('Android')).join('/');
          baseDir = Directory(p.join(publicPath, 'Music', 'Replay'));
        } else {
          baseDir = await getApplicationDocumentsDirectory();
        }
      }
    } else if (!kIsWeb && Platform.isIOS) {
      // On iOS, save to documents directory (accessible via Files app)
      baseDir = await getApplicationDocumentsDirectory();
    } else {
      // Windows, macOS, Linux - use documents directory
      baseDir = await getApplicationDocumentsDirectory();
    }

    // Create a folder structure like: recordings/2025-01/
    final yearMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthDir = Directory(p.join(baseDir.path, 'recordings', yearMonth));
    if (!monthDir.existsSync()) {
      monthDir.createSync(recursive: true);
    }

    // Create a filename with date and time: 2025-01-22_14-30-45.m4a
    final dateTime = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final filename = '$dateTime.$_fileExtension';

    final filePath = p.join(monthDir.path, filename);
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
