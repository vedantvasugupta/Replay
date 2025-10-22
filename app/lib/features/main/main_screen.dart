import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/uploads/audio_picker_service.dart';
import '../../core/uploads/upload_manager.dart';
import '../../state/auth_state.dart';
import '../../state/session_list_controller.dart';
import '../chats/chats_screen.dart';
import '../recording/recording_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Replay',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            onPressed: () => _handleUploadAudio(context),
            tooltip: 'Upload audio',
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            children: const [
              RecordingScreen(),
              ChatsScreen(),
            ],
          ),
          // Page indicator
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIndicator(0, 'Record'),
                const SizedBox(width: 32),
                _buildPageIndicator(1, 'Chats'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int index, String label) {
    final isActive = _currentPage == index;
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6366F1).withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF6366F1)
                : Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? const Color(0xFF6366F1)
                    : Colors.white.withOpacity(0.4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFF6366F1)
                    : Colors.white.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUploadAudio(BuildContext context) async {
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

      // Start upload in background (don't await)
      uploadManager.enqueueAndUpload(upload).then((_) {
        // Refresh after upload completes
        sessionNotifier.refresh();
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Uploading audio file... This may take a moment.'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
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
