import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/network.dart';
import 'session_providers.dart';

final recordInstanceProvider = Provider<AudioRecorder>((ref) => RecordAudioRecorder(Record()));

final recorderControllerProvider =
    StateNotifierProvider<RecorderController, RecorderState>((ref) {
  return RecorderController(ref.read);
});

class RecorderController extends StateNotifier<RecorderState> {
  RecorderController(this._read) : super(const RecorderState()) {
    _recorder = _read(recordInstanceProvider);
  }

  final Reader _read;
  late final AudioRecorder _recorder;
  Timer? _timer;

  Dio get _dio => _read(dioProvider);

  Future<void> start() async {
    if (state.status == RecorderStatus.recording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
        status: RecorderStatus.error,
        errorMessage: 'Recording permission denied',
      );
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final filePath =
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      path: filePath,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
    state = state.copyWith(
      status: RecorderStatus.recording,
      currentFilePath: filePath,
      elapsed: Duration.zero,
      resetError: true,
    );
  }

  Future<void> stopAndUpload() async {
    if (state.status != RecorderStatus.recording) return;
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path == null) {
      state = state.copyWith(
        status: RecorderStatus.error,
        errorMessage: 'Recording failed',
      );
      return;
    }
    state = state.copyWith(status: RecorderStatus.uploading, currentFilePath: path);
    await _upload(path);
  }

  Future<void> retryUpload() async {
    final path = state.currentFilePath;
    if (path == null) return;
    await _upload(path);
  }

  Future<void> _upload(String path) async {
    try {
      final file = File(path);
      final filename = path.split('/').last;
      final mime = filename.endsWith('.wav') ? 'audio/wav' : 'audio/m4a';
      final uploadUrlRes = await _dio.post('/upload-url', data: {
        'filename': filename,
        'mime': mime,
      });
      final uploadUrl = uploadUrlRes.data['uploadUrl'] as String;
      final assetId = uploadUrlRes.data['assetId'] as String;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: filename),
        'assetId': assetId,
      });
      await _dio.post(uploadUrl, data: formData);
      await _dio.post('/ingest', data: {'assetId': assetId});
      await file.delete();
      state = state.copyWith(
        status: RecorderStatus.success,
        currentFilePath: null,
        resetError: true,
      );
      await _read(sessionListProvider.notifier).load();
    } on DioException catch (e) {
      state = state.copyWith(
        status: RecorderStatus.error,
        errorMessage: e.response?.data['detail']?.toString() ?? 'Upload failed',
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

class RecorderState {
  const RecorderState({
    this.status = RecorderStatus.idle,
    this.elapsed = Duration.zero,
    this.currentFilePath,
    this.errorMessage,
  });

  final RecorderStatus status;
  final Duration elapsed;
  final String? currentFilePath;
  final String? errorMessage;

  RecorderState copyWith({
    RecorderStatus? status,
    Duration? elapsed,
    String? currentFilePath,
    String? errorMessage,
    bool resetError = false,
  }) {
    return RecorderState(
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      currentFilePath: currentFilePath ?? this.currentFilePath,
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

enum RecorderStatus { idle, recording, uploading, success, error }

abstract class AudioRecorder {
  Future<bool> hasPermission();
  Future<void> start({required String path, required AudioEncoder encoder, required int bitRate});
  Future<String?> stop();
  Future<void> dispose();
}

class RecordAudioRecorder implements AudioRecorder {
  RecordAudioRecorder(this._record);

  final Record _record;

  @override
  Future<void> dispose() => _record.dispose();

  @override
  Future<bool> hasPermission() => _record.hasPermission();

  @override
  Future<void> start({required String path, required AudioEncoder encoder, required int bitRate}) {
    return _record.start(path: path, encoder: encoder, bitRate: bitRate);
  }

  @override
  Future<String?> stop() => _record.stop();
}
