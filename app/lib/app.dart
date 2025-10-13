import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/uploads/upload_manager.dart';
import 'router/app_router.dart';

class ReplayApp extends ConsumerStatefulWidget {
  const ReplayApp({super.key});

  @override
  ConsumerState<ReplayApp> createState() => _ReplayAppState();
}

class _ReplayAppState extends ConsumerState<ReplayApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(uploadManagerProvider).retryPending());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Replay',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
