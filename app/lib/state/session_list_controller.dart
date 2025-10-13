import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sessions/session_repository.dart';
import '../domain/session_models.dart';

final sessionListControllerProvider =
    StateNotifierProvider<SessionListController, AsyncValue<List<SessionListItem>>>((ref) {
  final repository = ref.watch(sessionRepositoryProvider);
  return SessionListController(repository);
});

class SessionListController extends StateNotifier<AsyncValue<List<SessionListItem>>> {
  SessionListController(this._repository) : super(const AsyncValue.loading()) {
    refresh();
  }

  final SessionRepository _repository;

  Future<void> refresh() async {
    try {
      state = const AsyncValue.loading();
      final sessions = await _repository.fetchSessions();
      state = AsyncValue.data(sessions);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> deleteSession(int sessionId) async {
    try {
      await _repository.deleteSession(sessionId);
      await refresh();
    } catch (error, stack) {
      // Re-throw to allow UI to handle error
      rethrow;
    }
  }
}
