import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/recording/recording_service.dart';
import '../core/uploads/upload_manager.dart';

enum RecorderStatus { idle, recording, uploading, error }

class RecorderState {
  const RecorderState({
    required this.status,
    required this.elapsed,
    this.error,
  });

  final RecorderStatus status;
  final Duration elapsed;
  final String? error;

  RecorderState copyWith({RecorderStatus? status, Duration? elapsed, String? error}) {
    return RecorderState(
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      error: error,
    );
  }
}

final recorderControllerProvider = StateNotifierProvider<RecorderController, RecorderState>((ref) {
  final uploadManager = ref.watch(uploadManagerProvider);
  return RecorderController(uploadManager, RecordingService());
});

class RecorderController extends StateNotifier<RecorderState> {
  RecorderController(this._uploadManager, this._recordingService)
      : super(const RecorderState(status: RecorderStatus.idle, elapsed: Duration.zero));

  final UploadManager _uploadManager;
  final IRecordingService _recordingService;
  Timer? _ticker;

  Future<bool> start() async {
    try {
      final permitted = await _recordingService.canRecord();
      if (!permitted) {
        state = state.copyWith(
          status: RecorderStatus.error,
          error: 'Microphone permission denied or unavailable.',
        );
        return false;
      }
    } on UnsupportedError catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: error.message ?? 'Recording is not supported on this platform.',
      );
      return false;
    } on Exception catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: 'Failed to access microphone: $error',
      );
      return false;
    }
    try {
      await _recordingService.start();
      _startTicker();
      state = state.copyWith(status: RecorderStatus.recording, elapsed: Duration.zero, error: null);
      return true;
    } on UnsupportedError catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: error.message ?? 'Recording is not supported on this platform.',
      );
      return false;
    } on Exception catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: 'Failed to start recording: $error',
      );
      return false;
    }
  }

  Future<void> stop({String? title}) async {
    _stopTicker();
    state = state.copyWith(status: RecorderStatus.uploading, error: null);
    try {
      final result = await _recordingService.stop();
      if (result == null) {
        state = state.copyWith(status: RecorderStatus.idle, elapsed: Duration.zero);
        return;
      }
      final upload = PendingUpload(
        filePath: result.filePath,
        durationSec: result.duration.inSeconds.clamp(1, 24 * 3600).toInt(),
        mime: _mimeForPlatform(),
        createdAt: DateTime.now(),
        title: title,
      );
      await _uploadManager.enqueueAndUpload(upload);
      state = state.copyWith(status: RecorderStatus.idle, elapsed: Duration.zero);
    } on UnsupportedError catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: error.message ?? 'Recording is not supported on this platform.',
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: 'Failed to save recording: $error',
      );
    }
  }

  Future<void> cancel() async {
    _stopTicker();
    try {
      await _recordingService.cancel();
      state = state.copyWith(status: RecorderStatus.idle, elapsed: Duration.zero);
    } on UnsupportedError catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: error.message ?? 'Recording is not supported on this platform.',
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: RecorderStatus.error,
        error: 'Failed to cancel recording: $error',
      );
    }
  }

  Future<void> retryPending() => _uploadManager.retryPending();

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final newElapsed = state.elapsed + const Duration(seconds: 1);
      state = state.copyWith(elapsed: newElapsed);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  String _mimeForPlatform() {
    if (!kIsWeb && Platform.isWindows) {
      return 'audio/wav';
    }
    return 'audio/m4a';
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
