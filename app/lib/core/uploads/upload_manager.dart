import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import '../sessions/session_repository.dart';

final uploadManagerProvider = Provider<UploadManager>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return UploadManager(repository, prefs)..initialize();
});

class PendingUpload {
  PendingUpload({
    required this.filePath,
    required this.durationSec,
    required this.mime,
    required this.createdAt,
    this.title,
    this.attemptCount = 0,
    this.lastAttemptTime,
  });

  final String filePath;
  final int durationSec;
  final String mime;
  final DateTime createdAt;
  final String? title;
  final int attemptCount;
  final DateTime? lastAttemptTime;

  PendingUpload copyWith({
    String? filePath,
    int? durationSec,
    String? mime,
    DateTime? createdAt,
    String? title,
    int? attemptCount,
    DateTime? lastAttemptTime,
  }) {
    return PendingUpload(
      filePath: filePath ?? this.filePath,
      durationSec: durationSec ?? this.durationSec,
      mime: mime ?? this.mime,
      createdAt: createdAt ?? this.createdAt,
      title: title ?? this.title,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptTime: lastAttemptTime ?? this.lastAttemptTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'durationSec': durationSec,
        'mime': mime,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
        'attemptCount': attemptCount,
        'lastAttemptTime': lastAttemptTime?.toIso8601String(),
      };

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      filePath: json['filePath'] as String,
      durationSec: json['durationSec'] as int,
      mime: json['mime'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      title: json['title'] as String?,
      attemptCount: json['attemptCount'] as int? ?? 0,
      lastAttemptTime: json['lastAttemptTime'] != null
          ? DateTime.parse(json['lastAttemptTime'] as String)
          : null,
    );
  }
}

class UploadManager {
  UploadManager(this._repository, this._preferences);

  static const _storageKey = 'pending_uploads';
  static const _keepRecordingsLocallyKey = 'keep_recordings_locally';
  static const int maxRetries = 5;

  // Exponential backoff intervals in seconds: 30s, 2m, 10m, 30m, 60m
  static const List<int> retryBackoffSeconds = [30, 120, 600, 1800, 3600];

  final SessionRepository _repository;
  final SharedPreferences _preferences;
  final List<PendingUpload> _pending = [];
  bool _initialized = false;
  Future<void>? _ongoing;
  Timer? _retryTimer;

  bool get _keepRecordingsLocally => _preferences.getBool(_keepRecordingsLocallyKey) ?? false;

  int get pendingCount => _pending.length;

  List<PendingUpload> get pendingUploads => List.unmodifiable(_pending);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final raw = _preferences.getString(_storageKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      _pending
        ..clear()
        ..addAll(list.map(PendingUpload.fromJson));
    }
    _initialized = true;

    // Start periodic retry timer (check every 30 seconds)
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAndRetryPending();
    });

    // Trigger initial retry for any pending uploads
    Future.microtask(() => _checkAndRetryPending());
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Check if enough time has passed since last attempt based on exponential backoff
  bool _shouldRetry(PendingUpload upload) {
    // If never attempted or exceeded max retries, don't retry
    if (upload.attemptCount >= maxRetries) {
      return false;
    }

    // First attempt is always allowed
    if (upload.attemptCount == 0 || upload.lastAttemptTime == null) {
      return true;
    }

    // Calculate required backoff time for this attempt
    final backoffIndex = upload.attemptCount - 1;
    if (backoffIndex >= retryBackoffSeconds.length) {
      return false;
    }

    final requiredBackoff = Duration(seconds: retryBackoffSeconds[backoffIndex]);
    final timeSinceLastAttempt = DateTime.now().difference(upload.lastAttemptTime!);

    return timeSinceLastAttempt >= requiredBackoff;
  }

  /// Check all pending uploads and retry those that are ready
  Future<void> _checkAndRetryPending() async {
    if (!_initialized) {
      if (kDebugMode) {
        print('[UploadManager] Not initialized, skipping retry check');
      }
      return;
    }

    if (_ongoing != null) {
      if (kDebugMode) {
        print('[UploadManager] Upload already in progress, will retry later');
      }
      return;
    }

    for (final upload in List<PendingUpload>.from(_pending)) {
      if (_shouldRetry(upload)) {
        await _process(upload);
        // Only process one upload at a time
        break;
      }
    }
  }

  Future<void> enqueueAndUpload(PendingUpload upload) async {
    await initialize();
    _pending.add(upload);
    await _persist();
    await _process(upload);
  }

  Future<void> retryPending() async {
    if (!_initialized) {
      await initialize();
    }
    for (final upload in List<PendingUpload>.from(_pending)) {
      await _process(upload);
    }
  }

  Future<void> _process(PendingUpload upload) async {
    // Check if file still exists
    if (!File(upload.filePath).existsSync()) {
      if (kDebugMode) {
        print('[UploadManager] File not found, removing from queue: ${upload.filePath}');
      }
      _pending.remove(upload);
      await _persist();
      return;
    }

    // Check if we should retry this upload
    if (!_shouldRetry(upload)) {
      if (upload.attemptCount >= maxRetries) {
        if (kDebugMode) {
          print('[UploadManager] Max retries exceeded for: ${upload.filePath}');
          print('[UploadManager] Upload permanently failed after ${upload.attemptCount} attempts');
        }
      }
      return;
    }

    // Prevent concurrent uploads
    if (_ongoing != null) {
      if (kDebugMode) {
        print('[UploadManager] Upload already in progress, skipping: ${upload.filePath}');
      }
      return;
    }

    _ongoing = _execute(upload);
    try {
      await _ongoing;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[UploadManager] Error in _process: $e');
        print('[UploadManager] Stack trace: $stackTrace');
      }
    } finally {
      _ongoing = null;
    }
  }

  Future<void> _execute(PendingUpload upload) async {
    // Update retry metadata before attempting upload
    final attemptNumber = upload.attemptCount + 1;
    if (kDebugMode) {
      print('[UploadManager] Starting upload attempt $attemptNumber/${maxRetries + 1} for: ${upload.filePath}');
    }

    final updatedUpload = upload.copyWith(
      attemptCount: attemptNumber,
      lastAttemptTime: DateTime.now(),
    );

    // Update the upload in the pending list
    final index = _pending.indexWhere((u) => u.filePath == upload.filePath);
    if (index != -1) {
      _pending[index] = updatedUpload;
      await _persist();
    }

    try {
      // Validate file before upload
      final file = File(updatedUpload.filePath);
      if (!file.existsSync()) {
        throw Exception('File does not exist: ${updatedUpload.filePath}');
      }

      final fileSize = await file.length();
      if (kDebugMode) {
        print('[UploadManager] File validation - exists: true, size: $fileSize bytes');
      }

      if (fileSize == 0) {
        throw Exception('File is empty (0 bytes): ${updatedUpload.filePath}');
      }

      final allocation = await _repository.requestUpload(
        filename: File(updatedUpload.filePath).uri.pathSegments.last,
        mime: updatedUpload.mime,
      );
      if (kDebugMode) {
        print('[UploadManager] Got allocation, assetId: ${allocation.assetId}');
      }

      await _repository.uploadFile(
        assetId: allocation.assetId,
        file: File(updatedUpload.filePath),
        mime: updatedUpload.mime,
      );
      if (kDebugMode) {
        print('[UploadManager] File uploaded successfully');
      }

      final sessionId = await _repository.ingest(
        assetId: allocation.assetId,
        durationSec: updatedUpload.durationSec,
        title: updatedUpload.title,
      );
      if (kDebugMode) {
        print('[UploadManager] Ingest complete, sessionId: $sessionId');
      }

      // Only delete the file if the user hasn't opted to keep recordings locally
      if (!_keepRecordingsLocally) {
        await File(updatedUpload.filePath).delete().catchError((_) => File(''));
        if (kDebugMode) {
          print('[UploadManager] Local recording deleted after upload');
        }
      } else {
        if (kDebugMode) {
          print('[UploadManager] Local recording kept at: ${updatedUpload.filePath}');
        }
      }

      _pending.remove(updatedUpload);
      await _persist();
      if (kDebugMode) {
        print('[UploadManager] Upload completed successfully');
      }
    } catch (e, stackTrace) {
      // Always log errors, even in production (but with less verbosity)
      if (kDebugMode) {
        print('[UploadManager] Upload failed (attempt $attemptNumber/${maxRetries + 1}): $e');
        print('[UploadManager] Stack trace: $stackTrace');
      } else {
        print('[UploadManager] Upload failed (attempt $attemptNumber/${maxRetries + 1}): $e');
      }

      if (attemptNumber >= maxRetries) {
        if (kDebugMode) {
          print('[UploadManager] Max retries reached. Upload will not be retried automatically.');
          print('[UploadManager] File remains in queue. You can retry manually from the UI.');
        }
      } else {
        final nextBackoffIndex = attemptNumber - 1;
        if (nextBackoffIndex < retryBackoffSeconds.length) {
          final nextRetryIn = retryBackoffSeconds[nextBackoffIndex];
          if (kDebugMode) {
            print('[UploadManager] Will retry in $nextRetryIn seconds');
          }
        }
      }
      // Rethrow to ensure error is properly propagated
      rethrow;
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_pending.map((e) => e.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }
}
