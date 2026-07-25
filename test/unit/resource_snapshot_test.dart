import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _payload({
  List<Object?> sessions = const <Object?>[],
  bool warming = false,
}) {
  return <String, Object?>{
    'collectedAt': 1730000000000,
    'warming': warming,
    'host': <String, Object?>{
      'totalMemoryBytes': 16000000000,
      'availableMemoryBytes': 4000000000,
      'usedMemoryBytes': 12000000000,
      'memoryUsagePercent': 75.0,
      'cpuCoreCount': 8,
      'loadAverage1m': 1.25,
    },
    'processes': <String, Object?>{
      'host': <String, Object?>{
        'pid': 1001,
        'cpuPercent': 2.5,
        'memoryBytes': 40000000,
        'processCount': 1,
        'history': <Object?>[10, 20, 30],
      },
      'app': <String, Object?>{
        'pid': 1002,
        'cpuPercent': 0.5,
        'memoryBytes': 280000000,
        'processCount': 1,
        'history': <Object?>[100],
      },
    },
    'sessions': sessions,
    'totals': <String, Object?>{'cpuPercent': 12.5, 'memoryBytes': 900000000},
  };
}

void main() {
  group('ResourceSnapshot.fromJson', () {
    test('parses a full payload', () {
      final snapshot = ResourceSnapshot.fromJson(
        _payload(
          sessions: <Object?>[
            <String, Object?>{
              'sessionId': 's1',
              'workspaceId': 'w1',
              'tabId': 't1',
              'running': true,
              'shellPid': 4242,
              'measured': true,
              'cpuPercent': 12.0,
              'memoryBytes': 500000000,
              'processCount': 7,
              'history': <Object?>[1, 2],
            },
          ],
        ),
      );

      expect(snapshot.warming, isFalse);
      expect(snapshot.hasReading, isTrue);
      expect(
        snapshot.collectedAt,
        DateTime.fromMillisecondsSinceEpoch(1730000000000, isUtc: true),
      );
      expect(snapshot.host.cpuCoreCount, 8);
      expect(snapshot.host.loadAverage1m, 1.25);
      expect(snapshot.host.hasMemoryReading, isTrue);
      expect(snapshot.hostProcess?.pid, 1001);
      expect(snapshot.appProcess?.memoryBytes, 280000000);
      expect(snapshot.appProcess?.history, <int>[100]);
      expect(snapshot.totalCpuPercent, 12.5);
      expect(snapshot.totalMemoryBytes, 900000000);

      final session = snapshot.sessions.single;
      expect(session.sessionId, 's1');
      expect(session.workspaceId, 'w1');
      expect(session.tabId, 't1');
      expect(session.running, isTrue);
      expect(session.shellPid, 4242);
      expect(session.measured, isTrue);
      expect(session.processCount, 7);
      expect(session.history, <int>[1, 2]);
    });

    test('a warming payload is not a reading', () {
      final snapshot = ResourceSnapshot.fromJson(_payload(warming: true));

      expect(snapshot.warming, isTrue);
      expect(snapshot.hasReading, isFalse);
    });

    test('an exited session reports no shell pid', () {
      final snapshot = ResourceSnapshot.fromJson(
        _payload(
          sessions: <Object?>[
            <String, Object?>{
              'sessionId': 's1',
              'workspaceId': 'w1',
              'tabId': 't1',
              'running': false,
              'shellPid': null,
              'measured': false,
            },
          ],
        ),
      );

      final session = snapshot.sessions.single;
      expect(session.shellPid, isNull);
      expect(session.measured, isFalse);
      expect(session.memoryBytes, 0);
      expect(session.history, isEmpty);
    });

    test('tolerates an older host that omits fields', () {
      // The app can attach to a sidecar that predates a field, so a missing
      // value has to degrade instead of throwing.
      final snapshot = ResourceSnapshot.fromJson(<String, Object?>{});

      expect(snapshot.host, ResourceHostMetrics.empty);
      expect(snapshot.host.hasMemoryReading, isFalse);
      expect(snapshot.hostProcess, isNull);
      expect(snapshot.appProcess, isNull);
      expect(snapshot.sessions, isEmpty);
      expect(snapshot.totalMemoryBytes, 0);
    });

    test('drops session entries without an id', () {
      final snapshot = ResourceSnapshot.fromJson(
        _payload(
          sessions: <Object?>[
            'not a map',
            <String, Object?>{'workspaceId': 'w1'},
            <String, Object?>{'sessionId': ''},
            <String, Object?>{'sessionId': 'kept'},
          ],
        ),
      );

      expect(snapshot.sessions.map((session) => session.sessionId), <String>[
        'kept',
      ]);
    });
  });

  group('ResourceSnapshot.unavailable', () {
    test('carries the error and is not a reading', () {
      final snapshot = ResourceSnapshot.unavailable(error: 'host is down');

      expect(snapshot.error, 'host is down');
      expect(snapshot.hasReading, isFalse);
      expect(snapshot.sessions, isEmpty);
    });

    test('withError keeps the last good values visible', () {
      // A failed poll should not blank the panel: the previous numbers stay on
      // screen, flagged as stale.
      final snapshot = ResourceSnapshot.fromJson(_payload()).withError('boom');

      expect(snapshot.error, 'boom');
      expect(snapshot.hasReading, isFalse);
      expect(snapshot.totalMemoryBytes, 900000000);
      expect(snapshot.hostProcess?.pid, 1001);
    });
  });
}
