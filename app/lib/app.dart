import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/uploads/upload_manager.dart';
import 'core/sharing/share_handler_service.dart';
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
    Future.microtask(() {
      // Retry any pending uploads
      ref.read(uploadManagerProvider).retryPending();
      // Initialize share handler to receive shared audio files
      ref.read(shareHandlerServiceProvider).initialize();
    });
  }

  @override
  void dispose() {
    ref.read(shareHandlerServiceProvider).dispose();
    super.dispose();
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
