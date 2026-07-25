import 'dart:async';

import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';
import 'package:flutter_test/flutter_test.dart';

const Duration _fastDebounce = Duration(milliseconds: 5);
const Duration _fastMaxDelay = Duration(milliseconds: 20);
const Duration _fastRetry = Duration(milliseconds: 10);

RuntimeChangeCoalescer _coalescer() =>
    RuntimeChangeCoalescer(debounce: _fastDebounce, maxDelay: _fastMaxDelay);

void main() {
  test(
    'survives a failed snapshot read and recovers on host reconnect',
    () async {
      // Regression for the permanent freeze: an RPC timeout used to tear down
      // the shared connection, which killed the async* watcher for good and
      // left the workbench unable to see new workspaces or tabs.
      final client = _FakeRuntimeHostClient();
      final coalescer = _coalescer();
      var value = 'first';
      var failNext = false;
      final emitted = <String>[];
      var errored = false;
      var closed = false;

      final subscription =
          runtimeSnapshotStream<String>(
            client: client,
            eventNames: const <String>{'changed'},
            readSnapshot: () async {
              if (failNext) {
                throw StateError('connection closed');
              }
              return value;
            },
            coalesceKey: 'key',
            coalescer: coalescer,
            retryDelay: const Duration(seconds: 30),
          ).listen(
            emitted.add,
            onError: (Object _) => errored = true,
            onDone: () => closed = true,
          );
      addTearDown(subscription.cancel);

      await _settle();
      expect(emitted, <String>['first']);

      failNext = true;
      client.emit(const RuntimeHostEvent('changed', <String, Object?>{}));
      await _settle();

      expect(errored, isFalse, reason: 'the stream must never surface errors');
      expect(closed, isFalse, reason: 'the stream must never complete');
      expect(emitted, <String>['first']);

      failNext = false;
      value = 'second';
      client.emit(
        const RuntimeHostEvent(
          aleraRuntimeHostConnectedEvent,
          <String, Object?>{},
        ),
      );
      await _settle();

      expect(emitted, <String>['first', 'second']);
    },
  );

  test('retries a failed read on its own, which drives reconnection', () async {
    final client = _FakeRuntimeHostClient();
    final coalescer = _coalescer();
    var failures = 2;
    final emitted = <String>[];

    final subscription = runtimeSnapshotStream<String>(
      client: client,
      eventNames: const <String>{'changed'},
      readSnapshot: () async {
        if (failures > 0) {
          failures -= 1;
          throw StateError('host unavailable');
        }
        return 'ready';
      },
      coalesceKey: 'key',
      coalescer: coalescer,
      retryDelay: _fastRetry,
    ).listen(emitted.add);
    addTearDown(subscription.cancel);

    await _settle(const Duration(milliseconds: 120));
    expect(emitted, <String>['ready']);
    expect(failures, 0);
  });

  test('coalesces a burst of events into a single read', () async {
    final client = _FakeRuntimeHostClient();
    final coalescer = _coalescer();
    var reads = 0;

    final subscription = runtimeSnapshotStream<int>(
      client: client,
      eventNames: const <String>{'changed'},
      readSnapshot: () async => ++reads,
      coalesceKey: 'key',
      coalescer: coalescer,
    ).listen((_) {});
    addTearDown(subscription.cancel);

    await _settle();
    expect(reads, 1, reason: 'initial read');

    for (var i = 0; i < 10; i++) {
      client.emit(const RuntimeHostEvent('changed', <String, Object?>{}));
    }
    await _settle();

    expect(reads, 2, reason: '10 events must collapse into one read');
  });

  test('de-duplicates an event arriving while a read is in flight', () async {
    final client = _FakeRuntimeHostClient();
    final coalescer = _coalescer();
    var reads = 0;
    final gate = Completer<void>();

    final subscription = runtimeSnapshotStream<int>(
      client: client,
      eventNames: const <String>{'changed'},
      readSnapshot: () async {
        reads += 1;
        if (reads == 2) {
          await gate.future;
        }
        return reads;
      },
      coalesceKey: 'key',
      coalescer: coalescer,
    ).listen((_) {});
    addTearDown(subscription.cancel);

    await _settle();
    expect(reads, 1);

    client.emit(const RuntimeHostEvent('changed', <String, Object?>{}));
    await _settle();
    expect(reads, 2, reason: 'the second read is now in flight');

    for (var i = 0; i < 10; i++) {
      client.emit(const RuntimeHostEvent('changed', <String, Object?>{}));
    }
    gate.complete();
    await _settle();

    expect(reads, 3, reason: '10 events during a read must add one re-run');
  });

  test('RuntimeWorkbenchRepository keeps its tab stream alive after a failed '
      'list', () async {
    // Repository-level statement of the same contract: a torn-down connection
    // must not end the watcher that feeds new terminals into the workbench.
    final client = _FakeRuntimeHostClient()..failNextRequests = 1;
    final repository = RuntimeWorkbenchRepository(
      client,
      coalescer: _coalescer(),
    );
    client.responses['tab.list'] = <Object?>[];
    var errored = false;
    var closed = false;
    final emitted = <List<WorkspaceTabRecord>>[];

    final subscription = repository
        .watchWorkspaceTabs('workspace-1')
        .listen(
          emitted.add,
          onError: (Object _) => errored = true,
          onDone: () => closed = true,
        );
    addTearDown(subscription.cancel);

    await _settle();
    expect(errored, isFalse);
    expect(closed, isFalse);
    expect(emitted, isEmpty);

    client.emit(
      const RuntimeHostEvent(
        aleraRuntimeHostConnectedEvent,
        <String, Object?>{},
      ),
    );
    await _settle();

    expect(emitted, hasLength(1));
  });

  group('scope filtering', () {
    // Backward compatibility contract: an older host broadcasts change events
    // with an empty payload, so an absent or empty scope means wildcard and a
    // new app stays correct against a host that is already running.
    Future<int> readsFor(Map<String, Object?> payload) async {
      final client = _FakeRuntimeHostClient();
      final coalescer = _coalescer();
      var reads = 0;
      final subscription = runtimeSnapshotStream<int>(
        client: client,
        eventNames: const <String>{'changed'},
        readSnapshot: () async => ++reads,
        coalesceKey: 'key',
        coalescer: coalescer,
        matchesScope: runtimeScopeMatcher('workspaceId', 'mine'),
      ).listen((_) {});
      addTearDown(subscription.cancel);
      await _settle();
      reads = 0;
      client.emit(RuntimeHostEvent('changed', payload));
      await _settle();
      return reads;
    }

    test('ignores an event scoped to another workspace', () async {
      expect(await readsFor(<String, Object?>{'workspaceId': 'other'}), 0);
    });

    test('accepts an unscoped event from an older host', () async {
      expect(await readsFor(const <String, Object?>{}), 1);
    });

    test('accepts an event scoped to this workspace', () async {
      expect(await readsFor(<String, Object?>{'workspaceId': 'mine'}), 1);
    });
  });
}

Future<void> _settle([
  Duration duration = const Duration(milliseconds: 60),
]) async {
  await Future<void>.delayed(duration);
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final _events = StreamController<RuntimeHostEvent>.broadcast();
  final responses = <String, Object?>{};

  /// Number of upcoming requests that fail, modelling a torn-down connection.
  int failNextRequests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (failNextRequests > 0) {
      failNextRequests -= 1;
      throw StateError('terminal host connection closed');
    }
    return responses[type];
  }

  void emit(RuntimeHostEvent event) => _events.add(event);
}
