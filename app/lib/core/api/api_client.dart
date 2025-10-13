import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import '../../state/auth_state.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final env = ref.watch(envProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  return ApiClient(ref, dio);
});

class ApiClient {
  ApiClient(this._ref, this._dio) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.extra['skipAuth'] == true) {
          return handler.next(options);
        }
        final tokens = _ref.read(authControllerProvider).tokens;
        if (tokens != null) {
          options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && error.requestOptions.extra['skipAuth'] != true) {
          final retried = await _handleUnauthorized(error.requestOptions);
          if (retried != null) {
            return handler.resolve(retried);
          }
        }
        return handler.next(error);
      },
    ));
  }

  final Ref _ref;
  final Dio _dio;
  Completer<Response<dynamic>?>? _refreshLock;

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<dynamic>?> _handleUnauthorized(RequestOptions request) async {
    if (_refreshLock != null) {
      return _refreshLock!.future;
    }
    final tokens = _ref.read(authControllerProvider).tokens;
    if (tokens == null) {
      await _ref.read(authControllerProvider.notifier).signOut();
      return null;
    }

    _refreshLock = Completer<Response<dynamic>?>();
    try {
      final newTokens = await _ref.read(authControllerProvider.notifier).refreshTokens();
      if (newTokens == null) {
        _refreshLock!.complete(null);
        return null;
      }

      final options = Options(
        method: request.method,
        headers: Map<String, dynamic>.from(request.headers)
          ..['Authorization'] = 'Bearer ${newTokens.accessToken}',
        contentType: request.contentType,
        responseType: request.responseType,
        extra: request.extra,
      );
      final response = await _dio.request<dynamic>(
        request.path,
        data: request.data,
        queryParameters: request.queryParameters,
        options: options,
      );
      _refreshLock!.complete(response);
      return response;
    } on DioException {
      await _ref.read(authControllerProvider.notifier).signOut();
      _refreshLock!.complete(null);
      return null;
    } finally {
      _refreshLock = null;
    }
  }
}
