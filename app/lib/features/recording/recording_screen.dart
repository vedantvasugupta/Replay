import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/recorder_controller.dart';
import '../../state/session_list_controller.dart';
import '../home/widgets/animated_mic_button.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorder = ref.watch(recorderControllerProvider);
    final recorderNotifier = ref.read(recorderControllerProvider.notifier);
    final sessionNotifier = ref.read(sessionListControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer display
              if (recorder.status == RecorderStatus.recording) ...[
                _TimerDisplay(duration: recorder.elapsed),
                const SizedBox(height: 48),
              ],

              // Animated mic button
              AnimatedMicButton(
                state: _getMicButtonState(recorder.status),
                onTap: recorder.status == RecorderStatus.uploading
                    ? null
                    : () => _handleMicTap(context, ref, recorder.status, recorderNotifier, sessionNotifier),
                size: 200,
              ),

              const SizedBox(height: 32),

              // Status text
              Text(
                _getStatusText(recorder.status),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.7),
                  letterSpacing: 0.5,
                ),
              ),

              // Error message
              if (recorder.error != null) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    recorder.error!,
                    style: const TextStyle(
                      color: Color(0xFFFF3B30),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  MicButtonState _getMicButtonState(RecorderStatus status) {
    switch (status) {
      case RecorderStatus.idle:
      case RecorderStatus.error:
        return MicButtonState.idle;
      case RecorderStatus.recording:
        return MicButtonState.recording;
      case RecorderStatus.uploading:
        return MicButtonState.uploading;
    }
  }

  String _getStatusText(RecorderStatus status) {
    switch (status) {
      case RecorderStatus.idle:
        return 'Tap to start recording';
      case RecorderStatus.recording:
        return 'Recording... Tap to stop';
      case RecorderStatus.uploading:
        return 'Uploading recording...';
      case RecorderStatus.error:
        return 'Unable to record';
    }
  }

  Future<void> _handleMicTap(
    BuildContext context,
    WidgetRef ref,
    RecorderStatus status,
    RecorderController recorderNotifier,
    SessionListController sessionNotifier,
  ) async {
    switch (status) {
      case RecorderStatus.idle:
      case RecorderStatus.error:
        final started = await recorderNotifier.start();
        if (!started && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone permission is required.'),
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        break;
      case RecorderStatus.recording:
        await recorderNotifier.stop();
        await sessionNotifier.refresh();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Recording saved. AI transcription may take 1-2 minutes.'),
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        break;
      case RecorderStatus.uploading:
        break;
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
      style: const TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w300,
        letterSpacing: 4,
        fontFeatures: [
          FontFeature.tabularFigures(),
        ],
      ),
    );
  }
}
