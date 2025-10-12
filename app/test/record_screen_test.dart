import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:replay_app/features/recording/record_screen.dart';
import 'package:replay_app/providers/recorder_provider.dart';

class _FakeRecorderController extends RecorderController {
  _FakeRecorderController(super.read);

  @override
  Future<void> retryUpload() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stopAndUpload() async {}
}

class _FakeAudioRecorder implements AudioRecorder {
  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start({required String path, required AudioEncoder encoder, required int bitRate}) async {}

  @override
  Future<String?> stop() async => '';
}

void main() {
  testWidgets('record screen shows idle state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordInstanceProvider.overrideWithValue(_FakeAudioRecorder()),
          recorderControllerProvider.overrideWith((ref) => _FakeRecorderController(ref.read)),
        ],
        child: const MaterialApp(home: RecordScreen()),
      ),
    );

    expect(find.text('Tap to start recording'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
