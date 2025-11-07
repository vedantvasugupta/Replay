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
  ChatController(this._repository, this._sessionId) : super(const AsyncValue.data([])) {
    _loadMessages();
  }

  final SessionRepository _repository;
  final int _sessionId;
  bool _sending = false;

  Future<void> _loadMessages() async {
    state = const AsyncValue.loading();
    try {
      final messages = await _repository.fetchMessages(_sessionId);
      state = AsyncValue.data(messages);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> sendMessage(String message) async {
    if (_sending) {
      return;
    }
    _sending = true;
    final current = state.value ?? [];
    final userMessage = ChatMessage(role: 'user', content: message, createdAt: DateTime.now());
    final thinkingMessage = ChatMessage(
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    );
    state = AsyncValue.data([...current, userMessage, thinkingMessage]);
    try {
      final response = await _repository.sendChat(_sessionId, message);
      final assistant = ChatMessage(
        role: 'assistant',
        content: response.assistantMessage,
        citations: response.citations,
        createdAt: DateTime.now(),
      );
      final messages = <ChatMessage>[...(state.value ?? [])];
      final placeholderIndex = messages.lastIndexWhere((msg) => msg.isThinking && msg.role == 'assistant');
      if (placeholderIndex != -1) {
        messages[placeholderIndex] = assistant;
      } else {
        messages.add(assistant);
      }
      state = AsyncValue.data(messages);
    } catch (error, stack) {
      final messages = state.value ?? [];
      final cleaned = messages.where((msg) => !(msg.isThinking && msg.role == 'assistant')).toList();
      state = AsyncValue.data([
        ...cleaned,
        ChatMessage(
          role: 'assistant',
          content: 'Sorry, I ran into a problem answering that. Please try again.',
          createdAt: DateTime.now(),
        ),
      ]);
    } finally {
      _sending = false;
    }
  }
}
