import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const aiApiBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static Uri? validatedAiApiUri(
    String value, {
    bool releaseMode = kReleaseMode,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        (releaseMode && uri.scheme.toLowerCase() != 'https')) {
      return null;
    }
    return uri;
  }
}
