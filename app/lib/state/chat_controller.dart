import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sessions/session_repository.dart';
import '../domain/session_models.dart';

final chatControllerProvider = StateNotifierProvider.family<ChatController, AsyncValue<List<ChatMessage>>, int>(
  (ref, sessionId) {
    final repository = ref.watch(sessionRepositoryProvider);
    return ChatController(repository, sessionId);
  },
);

class ChatController extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  ChatController(this._repository, this._sessionId) : super(const AsyncValue.data([]));

  final SessionRepository _repository;
  final int _sessionId;
  bool _sending = false;

  Future<void> sendMessage(String message) async {
    if (_sending) {
      return;
    }
    _sending = true;
    final current = state.value ?? [];
    final userMessage = ChatMessage(role: 'user', content: message, createdAt: DateTime.now());
    state = AsyncValue.data([...current, userMessage]);
    try {
      final response = await _repository.sendChat(_sessionId, message);
      final assistant = ChatMessage(
        role: 'assistant',
        content: response.assistantMessage,
        citations: response.citations,
        createdAt: DateTime.now(),
      );
      state = AsyncValue.data([...state.value!, assistant]);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    } finally {
      _sending = false;
    }
  }
}
