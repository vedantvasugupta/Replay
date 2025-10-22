import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/recording/foreground_service_manager.dart';
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

class RecorderController extends StateNotifier<RecorderState> with WidgetsBindingObserver {
  RecorderController(this._uploadManager, this._recordingService)
      : super(const RecorderState(status: RecorderStatus.idle, elapsed: Duration.zero)) {
    _initializeForegroundService();
    WidgetsBinding.instance.addObserver(this);
  }

  final UploadManager _uploadManager;
  final IRecordingService _recordingService;
  Timer? _ticker;
  bool _isInBackground = false;

  Future<void> _initializeForegroundService() async {
    await ForegroundServiceManager.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _isInBackground = false;
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isInBackground = true;
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

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
      // Start foreground service before recording
      await ForegroundServiceManager.start();

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
    // Stop foreground service
    await ForegroundServiceManager.stop();

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
    // Stop foreground service
    await ForegroundServiceManager.stop();

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

      // Update foreground notification every 5 seconds
      if (newElapsed.inSeconds % 5 == 0) {
        ForegroundServiceManager.updateNotification(newElapsed);
      }
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
    WidgetsBinding.instance.removeObserver(this);
    ForegroundServiceManager.stop();
    super.dispose();
  }
}
