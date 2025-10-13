import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/auth_models.dart';
import '../providers.dart';

final credentialsStoreProvider = Provider<CredentialsStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CredentialsStore(prefs);
});

class CredentialsStore {
  CredentialsStore(this._preferences);

  static const _key = 'auth_tokens';

  final SharedPreferences _preferences;

  Future<void> save(AuthTokens tokens) async {
    await _preferences.setString(_key, jsonEncode(tokens.toJson()));
  }

  Future<AuthTokens?> read() async {
    final raw = _preferences.getString(_key);
    if (raw == null) {
      return null;
    }
    return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    await _preferences.remove(_key);
  }
}
