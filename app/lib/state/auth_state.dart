import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/credentials_store.dart';
import '../domain/auth_models.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.tokens,
    this.email,
    this.error,
    this.isLoading = false,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  final AuthStatus status;
  final AuthTokens? tokens;
  final String? email;
  final String? error;
  final bool isLoading;

  AuthState copyWith({
    AuthStatus? status,
    AuthTokens? tokens,
    String? email,
    String? error,
    bool? isLoading,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      tokens: tokens ?? this.tokens,
      email: email ?? this.email,
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final store = ref.watch(credentialsStoreProvider);
  return AuthController(repository, store);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._store) : super(const AuthState.unknown()) {
    _bootstrap();
  }

  final AuthRepository _repository;
  final CredentialsStore _store;

  Future<void> _bootstrap() async {
    final tokens = await _store.read();
    if (tokens != null) {
      // Try to validate tokens by attempting a refresh
      try {
        final refreshed = await _repository.refreshToken(tokens.refreshToken);
        await _store.save(refreshed);
        state = state.copyWith(status: AuthStatus.authenticated, tokens: refreshed, isLoading: false);
      } catch (e) {
        // Tokens are invalid (likely from different server), clear them
        await _store.clear();
        state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
    }
  }

  Future<void> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signUp(email: email, password: password);
      await signIn(email, password);
    } catch (error) {
      String errorMessage = 'Signup failed';
      if (error.toString().contains('400')) {
        errorMessage = 'Email already registered. Please login instead.';
      } else if (error.toString().contains('network') || error.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else {
        errorMessage = error.toString();
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await _repository.signIn(email: email, password: password);
      await _store.save(tokens);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        tokens: tokens,
        email: email,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      String errorMessage = 'Login failed';
      if (error.toString().contains('401')) {
        errorMessage = 'Invalid email or password. Please check your credentials or sign up.';
      } else if (error.toString().contains('network') || error.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else {
        errorMessage = error.toString();
      }
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false, error: errorMessage);
    }
  }

  Future<AuthTokens?> refreshTokens() async {
    final current = state.tokens;
    if (current == null) {
      return null;
    }
    try {
      final refreshed = await _repository.refreshToken(current.refreshToken);
      await _store.save(refreshed);
      state = state.copyWith(tokens: refreshed, status: AuthStatus.authenticated);
      return refreshed;
    } on Exception {
      await signOut();
      return null;
    }
  }

  Future<void> signOut() async {
    await _store.clear();
    state = state.copyWith(status: AuthStatus.unauthenticated, tokens: null, email: null, clearError: true);
  }

  Future<void> signInDebug({String email = 'debug@example.com'}) async {
    const tokens = AuthTokens(accessToken: 'debug-access-token', refreshToken: 'debug-refresh-token');
    await _store.save(tokens);
    state = state.copyWith(
      status: AuthStatus.authenticated,
      tokens: tokens,
      email: email,
      isLoading: false,
      clearError: true,
    );
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        state = state.copyWith(isLoading: false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Failed to get Google ID token');
      }

      final tokens = await _repository.signInWithGoogle(idToken);
      await _store.save(tokens);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        tokens: tokens,
        email: googleUser.email,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      String errorMessage = 'Google sign in failed';
      if (error.toString().contains('network') || error.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else {
        errorMessage = error.toString();
      }
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false, error: errorMessage);
    }
  }
}
