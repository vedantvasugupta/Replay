import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

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
    return await _recorder.hasPermission();
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
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(dir.path, 'recordings'));
    if (!recordingsDir.existsSync()) {
      recordingsDir.createSync(recursive: true);
    }
    final filename = '${const Uuid().v4()}.$_fileExtension';
    return p.join(recordingsDir.path, filename);
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
