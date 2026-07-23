import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareRuntimeHostVersions', () {
    test('orders semver cores', () {
      expect(compareRuntimeHostVersions('1.2.3', '1.2.4'), lessThan(0));
      expect(compareRuntimeHostVersions('1.3.0', '1.2.9'), greaterThan(0));
      expect(compareRuntimeHostVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareRuntimeHostVersions('1.2.3', '1.2.3'), 0);
    });

    test('treats missing patch as zero', () {
      expect(compareRuntimeHostVersions('1.2', '1.2.0'), 0);
      expect(isRuntimeHostVersionNewer('1.3', '1.2.9'), isTrue);
    });

    test('ignores pre-release metadata for core ordering', () {
      expect(compareRuntimeHostVersions('1.2.3-beta', '1.2.3'), 0);
      expect(isRuntimeHostVersionNewer('1.2.4-rc.1', '1.2.3'), isTrue);
    });
  });

  group('RuntimeHostStatusSnapshot.updateAvailable', () {
    test('is true only when bundled is strictly newer than running', () {
      expect(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '1.3.0',
          runtimeHostVersion: '1.2.3',
        ).updateAvailable,
        isTrue,
      );
      expect(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '1.2.3',
          runtimeHostVersion: '1.2.3',
        ).updateAvailable,
        isFalse,
      );
      expect(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '1.2.0',
          runtimeHostVersion: '1.2.3',
        ).updateAvailable,
        isFalse,
      );
      expect(
        const RuntimeHostStatusSnapshot(
          running: false,
          bundledVersion: '1.3.0',
          runtimeHostVersion: '1.2.3',
        ).updateAvailable,
        isFalse,
      );
    });
  });
}
