import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:replay_app/core/recording/recording_service.dart';
import 'package:replay_app/core/uploads/upload_manager.dart';
import 'package:replay_app/state/recorder_controller.dart';

class _FakeUploadManager implements UploadManager {
  @override
  Future<void> enqueueAndUpload(PendingUpload upload) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> retryPending() async {}
}

class _FakeRecordingService implements IRecordingService {
  bool started = false;

  @override
  Future<bool> canRecord() async => true;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<RecordingResult?> stop() async {
    started = false;
    return RecordingResult(filePath: 'file.m4a', duration: const Duration(seconds: 5));
  }

  @override
  Future<void> cancel() async {
    started = false;
  }
}

void main() {
  test('recorder controller transitions through states', () async {
    final controller = RecorderController(_FakeUploadManager(), _FakeRecordingService());
    expect(controller.state.status, RecorderStatus.idle);

    await controller.start();
    expect(controller.state.status, RecorderStatus.recording);

    await controller.stop();
    expect(controller.state.status, RecorderStatus.idle);
  });
}
