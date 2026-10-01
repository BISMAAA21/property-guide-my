import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/app/bootstrap.dart';

void main() {
  test('uses debug App Check locally and Play Integrity for release', () {
    expect(
      androidAppCheckProvider(releaseMode: false),
      isA<AndroidDebugProvider>(),
    );
    expect(
      androidAppCheckProvider(releaseMode: true),
      isA<AndroidPlayIntegrityProvider>(),
    );
  });
}
