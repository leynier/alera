import 'dart:async';

import 'package:alera/src/features/resource_manager/application/resource_manager_providers.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  _FakeRuntimeHostClient({this.payload, this.failure});

  final Object? payload;
  final Object? failure;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  final List<String> types = <String>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    types.add(type);
    requests.add(payload);
    if (failure != null) {
      throw failure!;
    }
    return this.payload;
  }
}

void main() {
  group('fetchResourceSnapshot', () {
    test(
      'sends the app pid so the host can attribute the app process',
      () async {
        final client = _FakeRuntimeHostClient(
          payload: <String, Object?>{
            'warming': false,
            'totals': <String, Object?>{'memoryBytes': 42},
          },
        );

        final snapshot = await fetchResourceSnapshot(
          client: client,
          appPid: 1234,
        );

        expect(client.types, <String>['resources.snapshot']);
        expect(client.requests.single['appPid'], 1234);
        expect(snapshot.totalMemoryBytes, 42);
        expect(snapshot.hasReading, isTrue);
      },
    );

    test('a host that rejects the verb degrades instead of throwing', () async {
      // An older sidecar has no resource monitor. The chip is ambient UI and
      // must not break the status bar when it is missing.
      final client = _FakeRuntimeHostClient(
        failure: StateError('Unsupported request type: resources.snapshot'),
      );

      final snapshot = await fetchResourceSnapshot(client: client, appPid: 1);

      expect(snapshot.hasReading, isFalse);
      expect(snapshot.error, contains('resources.snapshot'));
      expect(snapshot.sessions, isEmpty);
    });

    test('a non-object response is reported as an error', () async {
      final client = _FakeRuntimeHostClient(payload: 'nonsense');

      final snapshot = await fetchResourceSnapshot(client: client, appPid: 1);

      expect(snapshot.hasReading, isFalse);
      expect(snapshot.error, contains('unexpected resource payload'));
    });
  });

  group('polling cadence', () {
    test('the panel polls faster while it is open', () {
      // Open matches the host's own 2s sampling; closed keeps the chip fresh
      // without paying for a sweep nobody is watching.
      expect(resourceSnapshotOpenInterval, const Duration(seconds: 2));
      expect(resourceSnapshotClosedInterval, const Duration(seconds: 15));
      expect(
        resourceSnapshotClosedInterval,
        greaterThan(resourceSnapshotOpenInterval),
      );
    });
  });
}
