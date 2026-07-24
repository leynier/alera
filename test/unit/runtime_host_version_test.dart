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

    test('handles unparseable versions', () {
      expect(
        compareRuntimeHostVersions('dev', 'local'),
        'dev'.compareTo('local'),
      );
      expect(compareRuntimeHostVersions('not-a-version', '1.0.0'), lessThan(0));
      expect(
        compareRuntimeHostVersions('1.0.0', 'not-a-version'),
        greaterThan(0),
      );
      expect(compareRuntimeHostVersions('', '1.0.0'), lessThan(0));
      expect(compareRuntimeHostVersions('1.2.3.4', '1.2.3'), lessThan(0));
      expect(compareRuntimeHostVersions('1.-2.3', '1.0.0'), lessThan(0));
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
      expect(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '1.3.0',
          runtimeHostVersion: '',
        ).updateAvailable,
        isFalse,
      );
      expect(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '1.3.0',
        ).updateAvailable,
        isFalse,
      );
    });
  });

  group('RuntimeHostShutdownResult', () {
    test('parses json with and without optional counts', () {
      final full = RuntimeHostShutdownResult.fromJson(const <String, Object?>{
        'stopped': true,
        'forced': true,
        'activeSessions': 2,
        'activeJobs': 1,
        'activeAgents': 3,
      });
      expect(full.stopped, isTrue);
      expect(full.forced, isTrue);
      expect(full.activeSessions, 2);
      expect(full.activeJobs, 1);
      expect(full.activeAgents, 3);

      final sparse = RuntimeHostShutdownResult.fromJson(const <String, Object?>{
        'stopped': true,
        'forced': false,
      });
      expect(sparse.activeSessions, 0);
      expect(sparse.activeJobs, 0);
      expect(sparse.activeAgents, 0);
    });
  });

  group('RuntimeHostBusyException', () {
    test('stringifies to its message', () {
      // Non-const so coverage counts the constructor declaration line.
      final error = RuntimeHostBusyException(
        message: 'busy host',
        activeSessions: 1,
        activeJobs: 2,
      );
      expect(error.toString(), 'busy host');
      expect(error.activeSessions, 1);
      expect(error.activeJobs, 2);
    });
  });

  group('BundledSidecarVersion', () {
    test('stores version and optional commit', () {
      // Non-const so coverage counts the constructor declaration line.
      final withCommit = BundledSidecarVersion(
        version: '1.2.3',
        commit: 'abcdef',
      );
      expect(withCommit.version, '1.2.3');
      expect(withCommit.commit, 'abcdef');
      expect(BundledSidecarVersion(version: '1.0.0').commit, isNull);
    });
  });
}
