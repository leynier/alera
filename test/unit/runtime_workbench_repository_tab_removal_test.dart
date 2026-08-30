import 'dart:async';

import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replays tab removal once after an ambiguous timeout', () async {
    final client = _SequencedRuntimeHostClient(<Future<Object?> Function()>[
      () => Future<Object?>.error(
        const TerminalHostRequestTimeoutException(
          'tab.remove',
          Duration(seconds: 10),
        ),
      ),
      () async => null,
    ]);
    final repository = RuntimeWorkbenchRepository(client);

    await repository.removeWorkspaceTab('tab-1');

    expect(client.requests, <String>['tab.remove', 'tab.remove']);
    expect(client.payloads, <Map<String, Object?>>[
      <String, Object?>{'id': 'tab-1'},
      <String, Object?>{'id': 'tab-1'},
    ]);
  });

  test('replays tab removal once after the connection closes', () async {
    final client = _SequencedRuntimeHostClient(<Future<Object?> Function()>[
      () =>
          Future<Object?>.error(const TerminalHostConnectionClosedException()),
      () async => null,
    ]);
    final repository = RuntimeWorkbenchRepository(client);

    await repository.removeWorkspaceTab('tab-1');

    expect(client.requests, <String>['tab.remove', 'tab.remove']);
  });

  test('propagates a second tab removal timeout', () async {
    const first = TerminalHostRequestTimeoutException(
      'tab.remove',
      Duration(seconds: 10),
    );
    const second = TerminalHostRequestTimeoutException(
      'tab.remove',
      Duration(seconds: 10),
    );
    final client = _SequencedRuntimeHostClient(<Future<Object?> Function()>[
      () => Future<Object?>.error(first),
      () => Future<Object?>.error(second),
    ]);
    final repository = RuntimeWorkbenchRepository(client);

    await expectLater(
      repository.removeWorkspaceTab('tab-1'),
      throwsA(same(second)),
    );

    expect(client.requests, <String>['tab.remove', 'tab.remove']);
  });

  test('does not replay a non-transport tab removal failure', () async {
    final failure = StateError('tab removal was rejected');
    final client = _SequencedRuntimeHostClient(<Future<Object?> Function()>[
      () => Future<Object?>.error(failure),
    ]);
    final repository = RuntimeWorkbenchRepository(client);

    await expectLater(
      repository.removeWorkspaceTab('tab-1'),
      throwsA(same(failure)),
    );

    expect(client.requests, <String>['tab.remove']);
  });
}

final class _SequencedRuntimeHostClient(
  final List<Future<Object?> Function()> _responses,
) implements RuntimeHostClient {
  final requests = <String>[];
  final payloads = <Map<String, Object?>>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    requests.add(type);
    payloads.add(payload);
    return _responses.removeAt(0)();
  }
}
