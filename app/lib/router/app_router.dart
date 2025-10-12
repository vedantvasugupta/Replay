import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/welcome_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/home/home_screen.dart';
import '../features/recording/record_screen.dart';
import '../features/session/session_detail_screen.dart';
import '../providers/auth_providers.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier._redirect,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/signin',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/record',
        builder: (context, state) => const RecordScreen(),
      ),
      GoRoute(
        path: '/session/:id',
        builder: (context, state) => SessionDetailScreen(sessionId: state.pathParameters['id']!),
      ),
    ],
  );
});

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authNotifierProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  String? _redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authNotifierProvider);
    final loggingIn = state.matchedLocation == '/signin' || state.matchedLocation == '/signup';
    if (!auth.isAuthenticated) {
      return loggingIn ? null : '/';
    }
    if (loggingIn || state.matchedLocation == '/') {
      return '/home';
    }
    return null;
  }
}
