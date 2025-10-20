import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioPickerServiceProvider = Provider<AudioPickerService>((ref) {
  return AudioPickerService();
});

class AudioPickerResult {
  AudioPickerResult({
    required this.file,
    required this.mimeType,
    this.durationSec,
  });

  final File file;
  final String mimeType;
  final int? durationSec;
}

class AudioPickerService {
  static const List<String> _supportedExtensions = [
    'm4a',
    'mp3',
    'wav',
    'aac',
    'opus',
    'ogg',
    'flac',
    'wma',
    'aiff',
    'webm',
  ];

  static final Map<String, String> _extensionToMimeType = {
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

  Future<AudioPickerResult?> pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final pickedFile = result.files.first;
      if (pickedFile.path == null) {
        throw Exception('File path is null');
      }

      final file = File(pickedFile.path!);
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      // Get file extension and determine MIME type
      final extension = pickedFile.extension?.toLowerCase();
      final mimeType = extension != null ? _extensionToMimeType[extension] ?? 'audio/mpeg' : 'audio/mpeg';

      // Try to estimate duration (this is a rough estimate based on file size)
      // For accurate duration, you'd need to parse the audio file metadata
      final fileSize = await file.length();
      final estimatedDurationSec = _estimateDuration(fileSize, mimeType);

      return AudioPickerResult(
        file: file,
        mimeType: mimeType,
        durationSec: estimatedDurationSec,
      );
    } catch (e) {
      rethrow;
    }
  }

  int _estimateDuration(int fileSizeBytes, String mimeType) {
    // Very rough estimation based on common bitrates
    // For more accurate duration, you'd need an audio metadata library
    const avgBitrate = 128000; // 128 kbps average
    final durationSeconds = (fileSizeBytes * 8) ~/ avgBitrate;
    return durationSeconds > 0 ? durationSeconds : 60; // Default to 60 seconds if calculation fails
  }

  String getDisplayName(File file) {
    return file.path.split(Platform.pathSeparator).last;
  }

  Future<bool> validateAudioFile(File file) async {
    // Check if file exists
    if (!await file.exists()) {
      return false;
    }

    // Check file size (max 500 MB)
    final fileSize = await file.length();
    if (fileSize > 500 * 1024 * 1024) {
      return false;
    }

    // Check if file extension is supported
    final fileName = file.path.split(Platform.pathSeparator).last;
    final extension = fileName.split('.').last.toLowerCase();
    return _supportedExtensions.contains(extension);
  }
}
