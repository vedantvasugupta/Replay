import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/main/main_screen.dart';
import '../features/session_detail/session_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../state/auth_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: RouterRefresh(ref),
    redirect: (context, state) {
      final loggedIn = authState.status == AuthStatus.authenticated;
      final loggingIn = state.matchedLocation.startsWith('/auth');

      if (!loggedIn && !loggingIn) {
        return '/auth/sign-in';
      }
      if (loggedIn && loggingIn) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/sign-in',
        name: 'sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/auth/sign-up',
        name: 'sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const MainScreen(),
      ),
      GoRoute(
        path: '/session/:id',
        name: 'session-detail',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return SessionDetailScreen(sessionId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

class RouterRefresh extends ChangeNotifier {
  RouterRefresh(this._ref) {
    _sub = _ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
