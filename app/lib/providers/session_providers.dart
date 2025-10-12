import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/network.dart';

final sessionListProvider = StateNotifierProvider<SessionListNotifier, AsyncValue<List<SessionSummary>>>(
  (ref) => SessionListNotifier(ref.read)..load(),
);

class SessionListNotifier extends StateNotifier<AsyncValue<List<SessionSummary>>> {
  SessionListNotifier(this._read) : super(const AsyncValue.loading());

  final Reader _read;

  Dio get _dio => _read(dioProvider);

  Future<void> load() async {
    try {
      final response = await _dio.get('/sessions');
      final data = List<Map<String, dynamic>>.from(response.data as List);
      state = AsyncValue.data(data.map(SessionSummary.fromJson).toList());
    } on DioException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

final sessionDetailProvider = FutureProvider.family<SessionDetail, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/session/$id');
  return SessionDetail.fromJson(Map<String, dynamic>.from(response.data as Map));
});

final chatHistoryProvider = StateNotifierProvider.family<ChatNotifier, List<ChatMessage>, String>((ref, id) {
  return ChatNotifier(ref.read, id);
});

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier(this._read, this.sessionId) : super(const []);

  final Reader _read;
  final String sessionId;

  Dio get _dio => _read(dioProvider);

  Future<void> send(String message) async {
    final request = {'message': message};
    state = [
      ...state,
      ChatMessage(role: 'user', content: message, citations: const []),
    ];
    final response = await _dio.post('/session/$sessionId/chat', data: request);
    state = [
      ...state,
      ChatMessage.fromJson(Map<String, dynamic>.from(response.data as Map)),
    ];
  }
}
