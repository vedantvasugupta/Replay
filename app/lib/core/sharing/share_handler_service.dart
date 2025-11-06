import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../uploads/upload_manager.dart';
import '../../state/session_list_controller.dart';

final shareHandlerServiceProvider = Provider<ShareHandlerService>((ref) {
  return ShareHandlerService(ref);
});

// Provider to notify when files are shared
final sharedFilesNotifierProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>();
  ref.onDispose(() => controller.close());
  return controller.stream;
});

class ShareHandlerService {
  ShareHandlerService(this._ref);

  final Ref _ref;
  StreamSubscription? _intentDataStreamSubscription;

  /// Initialize the share handler service
  /// This should be called once when the app starts
  void initialize() {
    // Handle files shared when app is closed/killed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    });

    // Handle files shared while app is running
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
        }
      },
      onError: (err) {
        print('[ShareHandler] Error receiving shared files: $err');
      },
    );
  }

  /// Handle shared files by uploading them through the normal pipeline
  void _handleSharedFiles(List<SharedMediaFile> files) async {
    print('[ShareHandler] Received ${files.length} shared file(s)');

    final uploadManager = _ref.read(uploadManagerProvider);
    final sessionNotifier = _ref.read(sessionListControllerProvider.notifier);
    int successCount = 0;

    for (final sharedFile in files) {
      try {
        final filePath = sharedFile.path;
        final file = File(filePath);

        if (!await file.exists()) {
          print('[ShareHandler] Shared file does not exist: $filePath');
          continue;
        }

        // Validate file size (max 500 MB)
        final fileSize = await file.length();
        if (fileSize > 500 * 1024 * 1024) {
          print('[ShareHandler] File too large (${fileSize / (1024 * 1024)}MB): $filePath');
          continue;
        }

        // Determine MIME type from file extension
        final extension = filePath.split('.').last.toLowerCase();
        final mimeType = _getMimeType(extension);

        if (mimeType == null) {
          print('[ShareHandler] Unsupported file type: $extension');
          continue;
        }

        // Estimate duration (rough estimate based on file size)
        final estimatedDurationSec = _estimateDuration(fileSize);

        // Extract filename without extension for title
        final fileName = filePath.split(Platform.pathSeparator).last;
        final title = fileName.replaceAll(RegExp(r'\.[^.]*$'), '');

        print('[ShareHandler] Uploading shared file: $fileName (${fileSize / (1024 * 1024)}MB, ~${estimatedDurationSec}s)');

        // Create pending upload
        final upload = PendingUpload(
          filePath: filePath,
          durationSec: estimatedDurationSec,
          mime: mimeType,
          createdAt: DateTime.now(),
          title: title,
        );

        // Enqueue and upload
        await uploadManager.enqueueAndUpload(upload);

        print('[ShareHandler] Successfully enqueued shared file for upload');
        successCount++;
      } catch (e) {
        print('[ShareHandler] Error handling shared file: $e');
      }
    }

    // Refresh session list to show the new uploads
    if (successCount > 0) {
      await sessionNotifier.refresh();
      print('[ShareHandler] Successfully processed $successCount shared file(s)');
    }

    // Clear the shared files after processing
    ReceiveSharingIntent.instance.reset();
  }

  /// Get MIME type from file extension
  String? _getMimeType(String extension) {
    const mimeTypes = {
      'm4a': 'audio/mp4',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'opus': 'audio/opus',
      'ogg': 'audio/ogg',
      'flac': 'audio/flac',
      'wma': 'audio/x-ms-wma',
      'aiff': 'audio/aiff',
      'webm': 'audio/webm',
    };
    return mimeTypes[extension];
  }

  /// Estimate duration based on file size (rough approximation)
  int _estimateDuration(int fileSizeBytes) {
    const avgBitrate = 128000; // 128 kbps average
    final durationSeconds = (fileSizeBytes * 8) ~/ avgBitrate;
    return durationSeconds > 0 ? durationSeconds : 60; // Default to 60 seconds if calculation fails
  }

  /// Dispose and clean up subscriptions
  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
