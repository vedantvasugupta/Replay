import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/network.dart';

class AuthState {
  const AuthState({
    this.email,
    this.tokens,
    this.status = AuthStatus.signedOut,
  });

  final String? email;
  final AuthTokens? tokens;
  final AuthStatus status;

  bool get isAuthenticated => tokens != null;

  AuthState copyWith({
    String? email,
    AuthTokens? tokens,
    AuthStatus? status,
  }) {
    return AuthState(
      email: email ?? this.email,
      tokens: tokens ?? this.tokens,
      status: status ?? this.status,
    );
  }
}

enum AuthStatus { signedOut, authenticating, authenticated, error }

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._read) : super(const AuthState());

  final Reader _read;

  Dio get _dio => _read(dioProvider);
  Future<void> signup(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating);
    try {
      await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
      }, options: Options(extra: {'skipAuth': true}));
      await login(email, password);
    } on DioException catch (e) {
      state = state.copyWith(status: AuthStatus.error);
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating);
    try {
      final res = await _dio.post('/auth/login',
          data: {'email': email, 'password': password},
          options: Options(extra: {'skipAuth': true}));
      final tokens = AuthTokens.fromJson(Map<String, dynamic>.from(res.data as Map));
      state = AuthState(email: email, tokens: tokens, status: AuthStatus.authenticated);
    } on DioException {
      state = state.copyWith(status: AuthStatus.error);
      rethrow;
    }
  }

  Future<bool> tryRefresh({Dio? dio}) async {
    final refresh = state.tokens?.refresh;
    if (refresh == null) return false;
    final client = dio ?? _dio;
    try {
      final response = await client.post('/auth/refresh',
          data: {'refresh': refresh},
          options: Options(extra: {'skipAuth': true}));
      final tokens = AuthTokens.fromJson(Map<String, dynamic>.from(response.data as Map));
      state = state.copyWith(tokens: tokens, status: AuthStatus.authenticated);
      return true;
    } on DioException {
      state = const AuthState(status: AuthStatus.error);
      return false;
    }
  }

  void logout() {
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read);
});
