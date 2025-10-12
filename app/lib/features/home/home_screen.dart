import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_providers.dart';
import '../../providers/session_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'uploaded':
        return 'Uploaded';
      case 'processing':
        return 'Processing';
      case 'ready':
        return 'Ready';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'ready':
        return scheme.secondary;
      case 'processing':
        return scheme.tertiary;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);
    final formatter = DateFormat.yMMMd().add_Hm();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(authNotifierProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/record'),
        icon: const Icon(Icons.mic),
        label: const Text('Record'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionListProvider.notifier).load(),
        child: sessions.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Tap record to capture your first meeting.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final session = items[index];
                final subtitle = StringBuffer();
                if (session.durationSec != null) {
                  final mins = (session.durationSec! / 60).ceil();
                  subtitle.write('$mins min · ');
                }
                subtitle.write(_statusLabel(session.status));
                return ListTile(
                  title: Text(formatter.format(session.createdAt.toLocal())),
                  subtitle: Text(subtitle.toString()),
                  trailing: Chip(
                    backgroundColor: _statusColor(context, session.status).withOpacity(0.15),
                    label: Text(
                      _statusLabel(session.status),
                      style: TextStyle(color: _statusColor(context, session.status)),
                    ),
                  ),
                  onTap: () => context.go('/session/${session.id}'),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: items.length,
            );
          },
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text('Failed to load sessions: ${err is Exception ? err.toString() : 'Unknown error'}'),
              ),
              const SizedBox(height: 12),
              Center(
                child: FilledButton(
                  onPressed: () => ref.read(sessionListProvider.notifier).load(),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
