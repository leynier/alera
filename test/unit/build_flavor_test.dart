import 'package:alera/src/core/build_flavor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('effectiveAutoInstallEnabled', () {
    test('returns false on a dev build regardless of the requested flag', () {
      expect(
        effectiveAutoInstallEnabled(true, isDevBuild: true),
        isFalse,
        reason: 'dev flavor must hard-disable auto-update',
      );
      expect(
        effectiveAutoInstallEnabled(false, isDevBuild: true),
        isFalse,
      );
    });

    test('preserves the requested flag on a release build', () {
      expect(effectiveAutoInstallEnabled(true, isDevBuild: false), isTrue);
      expect(effectiveAutoInstallEnabled(false, isDevBuild: false), isFalse);
    });
  });
}
