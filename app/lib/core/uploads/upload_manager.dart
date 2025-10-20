import 'dart:convert';
import 'dart:io';

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
  });

  final String filePath;
  final int durationSec;
  final String mime;
  final DateTime createdAt;
  final String? title;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'durationSec': durationSec,
        'mime': mime,
        'createdAt': createdAt.toIso8601String(),
        'title': title,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      filePath: json['filePath'] as String,
      durationSec: json['durationSec'] as int,
      mime: json['mime'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      title: json['title'] as String?,
    );
  }
}

class UploadManager {
  UploadManager(this._repository, this._preferences);

  static const _storageKey = 'pending_uploads';

  final SessionRepository _repository;
  final SharedPreferences _preferences;
  final List<PendingUpload> _pending = [];
  bool _initialized = false;
  Future<void>? _ongoing;

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
    if (!File(upload.filePath).existsSync()) {
      _pending.remove(upload);
      await _persist();
      return;
    }
    _ongoing ??= _execute(upload);
    try {
      await _ongoing;
    } finally {
      _ongoing = null;
    }
  }

  Future<void> _execute(PendingUpload upload) async {
    try {
      print('[UploadManager] Starting upload for: ${upload.filePath}');

      final allocation = await _repository.requestUpload(
        filename: File(upload.filePath).uri.pathSegments.last,
        mime: upload.mime,
      );
      print('[UploadManager] Got allocation, assetId: ${allocation.assetId}');

      await _repository.uploadFile(
        assetId: allocation.assetId,
        file: File(upload.filePath),
        mime: upload.mime,
      );
      print('[UploadManager] File uploaded successfully');

      final sessionId = await _repository.ingest(
        assetId: allocation.assetId,
        durationSec: upload.durationSec,
        title: upload.title,
      );
      print('[UploadManager] Ingest complete, sessionId: $sessionId');

      await File(upload.filePath).delete().catchError((_) => File(''));
      _pending.remove(upload);
      await _persist();
      print('[UploadManager] Upload completed successfully');
    } catch (e, stackTrace) {
      print('[UploadManager] Upload failed: $e');
      print('[UploadManager] Stack trace: $stackTrace');
      // Keep upload in queue; will retry later.
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_pending.map((e) => e.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }
}
