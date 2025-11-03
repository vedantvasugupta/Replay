import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sessions/session_repository.dart';
import '../domain/session_models.dart';

final sessionDetailControllerProvider = StateNotifierProvider.family<
    SessionDetailController,
    AsyncValue<SessionDetail>,
    int>((ref, sessionId) {
  final repository = ref.watch(sessionRepositoryProvider);
  return SessionDetailController(repository, sessionId)..load();
});

class SessionDetailController extends StateNotifier<AsyncValue<SessionDetail>> {
  SessionDetailController(this._repository, this._sessionId) : super(const AsyncValue.loading());

  final SessionRepository _repository;
  final int _sessionId;
  Timer? _poller;

  Future<void> load() async {
    _poller?.cancel();
    try {
      final detail = await _repository.fetchSessionDetail(_sessionId);
      state = AsyncValue.data(detail);
      final needsRetry = detail.summary == null ||
          detail.transcript == null ||
          detail.meta.status != SessionStatus.ready;
      if (needsRetry) {
        _poller = Timer(const Duration(seconds: 3), () {
          load();
        });
      }
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refresh() => load();

  Future<void> updateTitle(String newTitle) async {
    final current = state.valueOrNull;
    await _repository.updateSessionTitle(_sessionId, newTitle);
    if (current != null) {
      state = AsyncValue.data(
        SessionDetail(
          meta: SessionMeta(
            id: current.meta.id,
            status: current.meta.status,
            createdAt: current.meta.createdAt,
            durationSec: current.meta.durationSec,
            title: newTitle,
          ),
          summary: current.summary,
          transcript: current.transcript,
        ),
      );
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }
}
