import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EnvConfig {
  EnvConfig({required this.apiBaseUrl});

  final String apiBaseUrl;
}

Future<EnvConfig> loadEnv() async {
  try {
    await dotenv.load(fileName: 'assets/env/.env');
  } catch (_) {
    await dotenv.load(fileName: 'assets/env/.env.example');
  }
  final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000';
  return EnvConfig(apiBaseUrl: apiBaseUrl);
}

final envProvider = Provider<EnvConfig>((ref) => throw UnimplementedError());
