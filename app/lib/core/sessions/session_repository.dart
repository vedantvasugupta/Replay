import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../domain/session_models.dart';
import '../api/api_client.dart';

class UploadAllocation {
  UploadAllocation({required this.assetId, required this.uploadUrl});

  final int assetId;
  final String uploadUrl;
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return SessionRepository(client);
});

class SessionRepository {
  SessionRepository(this._client);

  final ApiClient _client;

  Future<List<SessionListItem>> fetchSessions() async {
    final response = await _client.get<List<dynamic>>('/sessions');
    final data = response.data ?? [];
    return data.map((item) => SessionListItem.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<SessionDetail> fetchSessionDetail(int id) async {
    final response = await _client.get<Map<String, dynamic>>('/session/$id');
    return SessionDetail.fromJson(response.data!);
  }

  Future<ChatResponse> sendChat(int sessionId, String message) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/session/$sessionId/chat',
      data: {'message': message},
    );
    return ChatResponse.fromJson(response.data!);
  }

  Future<UploadAllocation> requestUpload({required String filename, required String mime}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/upload-url',
      data: {'filename': filename, 'mime': mime},
    );
    final data = response.data!;
    return UploadAllocation(
      assetId: data['assetId'] as int,
      uploadUrl: data['uploadUrl'] as String,
    );
  }

  Future<void> uploadFile({
    required int assetId,
    required File file,
    required String mime,
  }) async {
    final formData = FormData.fromMap({
      'assetId': assetId,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
        contentType: MediaType.parse(mime),
      ),
    });
    await _client.post('/upload', data: formData, options: Options(contentType: 'multipart/form-data'));
  }

  Future<int> ingest({
    required int assetId,
    required int durationSec,
    required String? title,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/ingest',
      data: {
        'assetId': assetId,
        'durationSec': durationSec,
        if (title != null) 'title': title,
      },
    );
    return response.data!['sessionId'] as int;
  }

  Future<void> deleteSession(int sessionId) async {
    await _client.delete('/session/$sessionId');
  }

  Future<void> updateSessionTitle(int sessionId, String title) async {
    await _client.patch(
      '/session/$sessionId/title',
      data: {'title': title},
    );
  }
}
