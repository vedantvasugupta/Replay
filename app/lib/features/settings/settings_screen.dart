import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../state/settings_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _buildSectionHeader('Recording'),
          SwitchListTile(
            title: const Text('Keep recordings locally'),
            subtitle: const Text('Save recordings on your device after upload'),
            value: settings.keepRecordingsLocally,
            onChanged: (value) {
              ref.read(settingsControllerProvider.notifier).setKeepRecordingsLocally(value);
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader('Account'),
          ListTile(
            title: const Text('Email'),
            subtitle: Text(authState.email ?? 'Not signed in'),
            leading: const Icon(Icons.email),
          ),
          ListTile(
            title: const Text('Sign out'),
            leading: const Icon(Icons.logout, color: Colors.red),
            textColor: Colors.red,
            onTap: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/signin');
              }
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader('About'),
          ListTile(
            title: const Text('Version'),
            subtitle: const Text('0.1.0'),
            leading: const Icon(Icons.info),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
