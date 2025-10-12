import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/recorder_provider.dart';

class RecordScreen extends ConsumerWidget {
  const RecordScreen({super.key});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recorderControllerProvider);
    final controller = ref.read(recorderControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Record meeting')),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatDuration(state.elapsed),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  if (state.status == RecorderStatus.recording) {
                    controller.stopAndUpload();
                  } else {
                    controller.start();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 160,
                  width: 160,
                  decoration: BoxDecoration(
                    color: state.status == RecorderStatus.recording
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Icon(
                    state.status == RecorderStatus.recording ? Icons.stop : Icons.mic,
                    size: 64,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                switch (state.status) {
                  RecorderStatus.recording => 'Recording… tap to stop',
                  RecorderStatus.uploading => 'Uploading…',
                  RecorderStatus.success => 'Upload complete!',
                  RecorderStatus.error => state.errorMessage ?? 'Something went wrong',
                  _ => 'Tap to start recording',
                },
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (state.status == RecorderStatus.error && state.currentFilePath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: controller.retryUpload,
                    child: const Text('Retry upload'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
