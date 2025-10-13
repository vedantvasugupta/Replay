import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth_models.dart';
import '../env.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final env = ref.watch(envProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  return AuthRepository(dio);
});

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<User> signUp({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/signup',
      data: {'email': email, 'password': password},
    );
    return User.fromJson(response.data!);
  }

  Future<AuthTokens> signIn({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = response.data!;
    return AuthTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
  }

  Future<AuthTokens> refreshToken(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data!;
    return AuthTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
  }

  Future<AuthTokens> signInWithGoogle(String idToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'idToken': idToken},
    );
    final data = response.data!;
    return AuthTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
  }
}
