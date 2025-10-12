import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../providers/auth_providers.dart';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final authNotifier = ref.read(authNotifierProvider.notifier);
  final dio = Dio(BaseOptions(
    baseUrl: config.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.extra['skipAuth'] == true) {
          return handler.next(options);
        }
        final token = ref.read(authNotifierProvider).tokens?.access;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && error.requestOptions.extra['retry'] != true) {
          final refreshed = await authNotifier.tryRefresh(dio: dio);
          if (refreshed) {
            final requestOptions = error.requestOptions;
            requestOptions.headers['Authorization'] =
                'Bearer ${ref.read(authNotifierProvider).tokens?.access}';
            requestOptions.extra['retry'] = true;
            final response = await dio.fetch(requestOptions);
            return handler.resolve(response);
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
