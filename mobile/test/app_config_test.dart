import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/shared/config/app_config.dart';

void main() {
  test('accepts HTTP only for local non-release development', () {
    expect(
      AppConfig.validatedAiApiUri('http://10.0.2.2:8000', releaseMode: false),
      Uri.parse('http://10.0.2.2:8000'),
    );
    expect(
      AppConfig.validatedAiApiUri('http://api.example.test', releaseMode: true),
      isNull,
    );
  });

  test('accepts HTTPS and rejects unsafe or ambiguous base URLs', () {
    expect(
      AppConfig.validatedAiApiUri(
        'https://api.example.test',
        releaseMode: true,
      ),
      Uri.parse('https://api.example.test'),
    );
    for (final value in [
      'ftp://api.example.test',
      'https://user:password@api.example.test',
      'https://api.example.test?token=value',
      'https://api.example.test/#fragment',
      'not-a-url',
    ]) {
      expect(
        AppConfig.validatedAiApiUri(value, releaseMode: false),
        isNull,
        reason: value,
      );
    }
  });
}
