import 'dart:async';

import 'package:alera/src/features/orchestration/application/run_board_providers.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _watchTests('board', runBoardSnapshotProvider(), _board);
  _watchTests('detail', orchestrationRunSnapshotProvider('run'), _detail);
}

void _watchTests<T>(
  String name,
  ProviderListenable<AsyncValue<T>> provider,
  Map<String, Object?> response,
) {
  group(name, () {
    test(
      'unsupported host stays visible without retries and recovers on event',
      () {
        fakeAsync((time) {
          final fixture = _Fixture(response);
          fixture.client.supported = false;
          final sub = fixture.container.listen(provider, (_, _) {});
          time.flushMicrotasks();
          final error = fixture.container.read(provider);
          expect(error.error, isA<RunBoardUpdateRequired>());
          expect(error.retrying, isFalse);
          time.elapse(const Duration(seconds: 2));
          expect(fixture.client.capabilityChecks, 1);
          expect(fixture.client.requests, 0);

          fixture.client.supported = true;
          fixture.client.emit(runBoardChangedEvent);
          time.elapse(const Duration(milliseconds: 10));
          expect(fixture.container.read(provider).hasValue, isTrue);
          expect(fixture.client.capabilityChecks, 2);
          expect(fixture.client.requests, 1);
          sub.close();
          fixture.dispose();
          time.flushMicrotasks();
          expect(fixture.client.events.hasListener, isFalse);
        });
      },
    );

    test(
      'request and disconnect errors do not retry without recovery events',
      () {
        fakeAsync((time) {
          final fixture = _Fixture(response);
          fixture.client.fail = true;
          final sub = fixture.container.listen(provider, (_, _) {});
          time.flushMicrotasks();
          expect(fixture.container.read(provider).error, isA<Exception>());
          expect(fixture.container.read(provider).retrying, isFalse);
          time.elapse(const Duration(seconds: 2));
          expect(fixture.client.requests, 1);

          fixture.client.fail = false;
          fixture.client.emit(aleraRuntimeHostConnectedEvent);
          time.elapse(const Duration(milliseconds: 10));
          expect(fixture.container.read(provider).hasValue, isTrue);
          fixture.client.emit(aleraRuntimeHostDisconnectedEvent);
          time.flushMicrotasks();
          final disconnected = fixture.container.read(provider);
          expect(
            disconnected.error,
            isA<TerminalHostConnectionClosedException>(),
          );
          expect(disconnected.retrying, isFalse);
          time.elapse(const Duration(seconds: 2));
          expect(fixture.client.capabilityChecks, 2);
          expect(fixture.client.requests, 2);
          sub.close();
          fixture.dispose();
          time.flushMicrotasks();
        });
      },
    );

    test(
      'disposing during the initial read drops late data and subscriptions',
      () {
        fakeAsync((time) {
          final fixture = _Fixture(response);
          final pending = Completer<Object?>();
          fixture.client.pending = pending.future;
          final values = <AsyncValue<T>>[];
          final sub = fixture.container.listen(
            provider,
            (_, next) => values.add(next),
            fireImmediately: true,
          );
          time.flushMicrotasks();
          expect(fixture.client.requests, 1);
          fixture.client.emit(runBoardChangedEvent);
          sub.close();
          fixture.container.dispose();
          time.flushMicrotasks();
          final delivered = values.length;
          expect(fixture.client.events.hasListener, isFalse);
          pending.complete(response);
          fixture.client.emit(runBoardChangedEvent);
          time.elapse(const Duration(seconds: 2));
          expect(values, hasLength(delivered));
          expect(fixture.client.requests, 1);
          fixture.dispose(containerDisposed: true);
          time.flushMicrotasks();
        });
      },
    );
  });
}

class _Fixture {
  _Fixture(Map<String, Object?> response) : client = _Client(response) {
    container = ProviderContainer(
      overrides: [
        runBoardRepositoryProvider.overrideWith(
          (_) => RuntimeRunBoardRepository(client, coalescer),
        ),
      ],
    );
  }

  final _Client client;
  final coalescer = RuntimeChangeCoalescer(
    debounce: const Duration(milliseconds: 5),
    maxDelay: const Duration(seconds: 5),
  );
  late final ProviderContainer container;

  void dispose({bool containerDisposed = false}) {
    if (!containerDisposed) container.dispose();
    coalescer.dispose();
    unawaited(client.events.close());
  }
}

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _Client(this.response);

  final Map<String, Object?> response;
  final events = StreamController<RuntimeHostEvent>.broadcast();
  Future<Object?>? pending;
  var supported = true;
  var fail = false;
  var capabilityChecks = 0;
  var requests = 0;

  void emit(String name) => events.add(RuntimeHostEvent(name, const {}));

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    expect(capability, aleraRuntimeHostRunBoardCapability);
    capabilityChecks++;
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> data = const {},
    Duration? timeout,
  ]) async {
    requests++;
    if (fail) throw Exception('Request failed');
    return await (pending ?? Future.value(response));
  }
}

const _board = <String, Object?>{
  'revision': 1,
  'counts': {'attention': 0, 'active': 0, 'history': 0},
  'items': [],
  'next_cursor': null,
};

const _detail = <String, Object?>{
  'revision': 1,
  'run': {
    'id': 'run',
    'objective': 'Objective',
    'status': 'running',
    'bucket': 'active',
    'workspace_id': 'owner',
    'created_at': '2026-08-29',
    'last_activity_at': '2026-08-29',
    'policy_status': 'approved',
    'task_count': 0,
    'completed_count': 0,
    'running_count': 0,
    'failed_count': 0,
    'stalled_count': 0,
    'blocked_count': 0,
    'pending_gate_count': 0,
  },
  'objective': 'Objective',
  'objective_truncated': false,
  'tasks': [],
  'next_task_id': null,
};
