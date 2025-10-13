import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/recorder_controller.dart';
import '../../state/session_list_controller.dart';

class RecordScreen extends ConsumerWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorder = ref.watch(recorderControllerProvider);
    final notifier = ref.read(recorderControllerProvider.notifier);

    Future<void> handleTap() async {
      switch (recorder.status) {
        case RecorderStatus.idle:
        case RecorderStatus.error:
          final started = await notifier.start();
          if (!started && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission is required.')),
            );
          }
          break;
        case RecorderStatus.recording:
          await notifier.stop();
          await ref.read(sessionListControllerProvider.notifier).refresh();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload queued. Processing will continue in background.')),
            );
          }
          break;
        case RecorderStatus.uploading:
          break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Record Meeting')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            _TimerDisplay(duration: recorder.elapsed),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: recorder.status == RecorderStatus.uploading ? null : handleTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: recorder.status == RecorderStatus.recording
                      ? Colors.redAccent
                      : Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  recorder.status == RecorderStatus.recording ? Icons.stop : Icons.mic,
                  size: 72,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(_statusLabel(recorder.status), style: Theme.of(context).textTheme.titleMedium),
            if (recorder.error != null) ...[
              const SizedBox(height: 16),
              Text(recorder.error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const Spacer(),
            TextButton(
              onPressed: () async {
                await notifier.retryPending();
                await ref.read(sessionListControllerProvider.notifier).refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Retry triggered for pending uploads')));
                }
              },
              child: const Text('Retry Pending Uploads'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(RecorderStatus status) {
    switch (status) {
      case RecorderStatus.idle:
        return 'Tap to start recording';
      case RecorderStatus.recording:
        return 'Recording… Tap to stop';
      case RecorderStatus.uploading:
        return 'Uploading recording…';
      case RecorderStatus.error:
        return 'Unable to record';
    }
  }
}

class _TimerDisplay extends StatelessWidget {
  const _TimerDisplay({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text(
      '$minutes:$seconds',
      style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
