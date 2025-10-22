import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/auth_models.dart';

final credentialsStoreProvider = Provider<CredentialsStore>((ref) {
  return CredentialsStore(const FlutterSecureStorage());
});

class CredentialsStore {
  CredentialsStore(this._storage);

  static const _key = 'auth_tokens';

  final FlutterSecureStorage _storage;

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: _key, value: jsonEncode(tokens.toJson()));
  }

  Future<AuthTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) {
      return null;
    }
    return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
