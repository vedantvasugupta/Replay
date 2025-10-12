import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl});
  final String apiBaseUrl;
}

final appConfigProvider = Provider<AppConfig>((ref) {
  final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';
  return AppConfig(apiBaseUrl: baseUrl);
});
