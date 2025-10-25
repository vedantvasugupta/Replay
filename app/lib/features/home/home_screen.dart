import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/uploads/audio_picker_service.dart';
import '../../core/uploads/upload_manager.dart';
import '../../domain/session_models.dart';
import '../../state/auth_state.dart';
import '../../state/recorder_controller.dart';
import '../../state/session_list_controller.dart';
import 'widgets/animated_mic_button.dart';
import 'widgets/session_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-refresh every 10 seconds to check for completed transcriptions
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _startAutoRefresh();
      }
    });
  }

  void _startAutoRefresh() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return false;

      final sessions = ref.read(sessionListControllerProvider);
      sessions.whenData((items) {
        // Check if any sessions are still processing
        final hasProcessing = items.any((s) => s.status == SessionStatus.processing);
        if (hasProcessing) {
          ref.read(sessionListControllerProvider.notifier).refreshSilently();
        }
      });

      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionListControllerProvider);
    final sessionNotifier = ref.read(sessionListControllerProvider.notifier);
    final recorder = ref.watch(recorderControllerProvider);
    final recorderNotifier = ref.read(recorderControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Replay',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.upload_file_rounded),
                        onPressed: () => _handleUploadAudio(context, ref),
                        tooltip: 'Upload audio',
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                        tooltip: 'Sign out',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Pending uploads banner
            _buildPendingUploadsBanner(ref),

            // Main recording area
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Timer display
                    if (recorder.status == RecorderStatus.recording) ...[
                      _TimerDisplay(duration: recorder.elapsed),
                      const SizedBox(height: 32),
                    ],

                    // Animated mic button
                    AnimatedMicButton(
                      state: _getMicButtonState(recorder.status),
                      onTap: recorder.status == RecorderStatus.uploading
                          ? null
                          : () => _handleMicTap(context, ref, recorder.status, recorderNotifier, sessionNotifier),
                      size: 180,
                    ),

                    const SizedBox(height: 24),

                    // Status text
                    Text(
                      _getStatusText(recorder.status),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.5,
                      ),
                    ),

                    // Error message
                    if (recorder.error != null) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
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

            // Past recordings section
            SizedBox(
              height: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Past Recordings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.9),
                            letterSpacing: 0.15,
                          ),
                        ),
                        sessions.maybeWhen(
                          data: (items) => Text(
                            '${items.length}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: sessions.when(
                      data: (items) => items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'No recordings yet.\nTap the mic to start your first session.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.5),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: sessionNotifier.refresh,
                              backgroundColor: const Color(0xFF1E1E1E),
                              color: const Color(0xFF6366F1),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final session = items[index];
                                  return SessionCard(
                                    session: session,
                                    onTap: () => context.go('/home/session/${session.id}'),
                                    onDelete: () async {
                                      try {
                                        await sessionNotifier.deleteSession(session.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: const Text('Recording deleted successfully'),
                                              backgroundColor: const Color(0xFF1E1E1E),
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to delete: $e'),
                                              backgroundColor: const Color(0xFFFF3B30),
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      error: (error, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 48,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load recordings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error.toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: sessionNotifier.refresh,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingUploadsBanner(WidgetRef ref) {
    final uploadManager = ref.watch(uploadManagerProvider);
    final pendingCount = uploadManager.pendingCount;

    if (pendingCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9500).withOpacity(0.15),
        border: Border.all(
          color: const Color(0xFFFF9500).withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            color: const Color(0xFFFF9500),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$pendingCount recording${pendingCount > 1 ? 's' : ''} pending upload',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final recorderNotifier = ref.read(recorderControllerProvider.notifier);
              await recorderNotifier.retryPending();

              messenger.showSnackBar(
                SnackBar(
                  content: Text('Retrying $pendingCount upload${pendingCount > 1 ? 's' : ''}...'),
                  backgroundColor: const Color(0xFF1E1E1E),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9500),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text(
              'Retry All',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  MicButtonState _getMicButtonState(RecorderStatus status) {
    switch (status) {
      case RecorderStatus.idle:
      case RecorderStatus.error:
        return MicButtonState.idle;
      case RecorderStatus.recording:
      case RecorderStatus.paused:
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
      case RecorderStatus.paused:
        return 'Recording paused (auto-resuming)';
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

  Future<void> _handleUploadAudio(BuildContext context, WidgetRef ref) async {
    try {
      final audioPicker = ref.read(audioPickerServiceProvider);
      final uploadManager = ref.read(uploadManagerProvider);
      final sessionNotifier = ref.read(sessionListControllerProvider.notifier);

      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Selecting audio file...'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }

      // Pick audio file
      final result = await audioPicker.pickAudioFile();

      if (result == null) {
        // User cancelled the picker
        return;
      }

      // Validate the audio file
      final isValid = await audioPicker.validateAudioFile(result.file);
      if (!isValid) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Invalid audio file. Please select a supported audio file (max 500MB).'),
              backgroundColor: const Color(0xFFFF3B30),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      // Show upload progress
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Uploading audio file...'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }

      // Create pending upload and enqueue
      final fileName = audioPicker.getDisplayName(result.file);
      final upload = PendingUpload(
        filePath: result.file.path,
        durationSec: result.durationSec ?? 0,
        mime: result.mimeType,
        createdAt: DateTime.now(),
        title: fileName.replaceAll(RegExp(r'\.[^.]*$'), ''), // Remove file extension for title
      );

      await uploadManager.enqueueAndUpload(upload);

      // Refresh session list
      await sessionNotifier.refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Audio uploaded successfully! AI transcription may take 1-2 minutes.'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload audio: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
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
        fontSize: 48,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
        fontFeatures: [
          FontFeature.tabularFigures(),
        ],
      ),
    );
  }
}
