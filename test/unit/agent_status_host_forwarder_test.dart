import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_host_forwarder.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRuntimeHostClient implements RuntimeHostClient {
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  final List<Completer<Object?>> queuedResults = <Completer<Object?>>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  Object? error;
  int attempts = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  void emitRuntimeHostConnected() {
    _events.add(
      const RuntimeHostEvent(
        aleraRuntimeHostConnectedEvent,
        <String, Object?>{},
      ),
    );
  }

  Future<void> dispose() => _events.close();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    attempts += 1;
    if (queuedResults.isNotEmpty) {
      final result = queuedResults.removeAt(0);
      final value = await result.future;
      requests.add((type, payload));
      return value;
    }
    if (error != null) {
      throw error!;
    }
    requests.add((type, payload));
    return null;
  }
}

AgentStatusEntry _entry(
  String sessionId, {
  AgentStatusState state = AgentStatusState.working,
  AgentType agentType = AgentType.claude,
}) {
  final now = DateTime.utc(2026, 7, 5);
  return AgentStatusEntry(
    terminalSessionId: sessionId,
    workspaceId: 'ws-1',
    tabId: 'tab-1',
    agentType: agentType,
    state: state,
    prompt: '',
    updatedAt: now,
    stateStartedAt: now,
  );
}

void main() {
  late _RecordingRuntimeHostClient client;
  late AgentStatusHostForwarder forwarder;

  setUp(() {
    client = _RecordingRuntimeHostClient();
    forwarder = AgentStatusHostForwarder(client: client, debounce: .zero);
  });

  tearDown(() async {
    forwarder.dispose();
    await client.dispose();
  });

  Future<void> pumpDebounce() async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  List<Map<String, Object?>> sentEntries() {
    expect(client.requests, hasLength(1));
    final (type, payload) = client.requests.single;
    expect(type, 'orchestration.agentStatus');
    return (payload['entries']! as List<Object?>).cast<Map<String, Object?>>();
  }

  test('forwards state transitions with session identity', () async {
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1', state: .waiting),
    });
    await pumpDebounce();

    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['state'], 'waiting');
    expect(entries.single['agentType'], 'claude');
    expect(entries.single['workspaceId'], 'ws-1');
    expect(entries.single['tabId'], 'tab-1');
    expect(entries.single['stateStartedAt'], '2026-07-05T00:00:00.000Z');
  });

  test('skips entries whose state and agent type are unchanged', () async {
    final before = {'s1': _entry('s1'), 's2': _entry('s2')};
    final after = {'s1': _entry('s1'), 's2': _entry('s2', state: .waiting)};
    forwarder.onStatusChanged(before, after);
    await pumpDebounce();

    final entries = sentEntries();
    expect(entries, hasLength(1));
    expect(entries.single['terminalSessionId'], 's2');
  });

  test('replays current presence snapshot after host reconnect', () async {
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1', state: .waiting),
    });
    await pumpDebounce();
    expect(client.requests, hasLength(1));
    client.requests.clear();

    client.emitRuntimeHostConnected();
    await pumpDebounce();

    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['state'], 'waiting');
  });

  test('reports removed sessions', () async {
    forwarder.onStatusChanged({
      's1': _entry('s1'),
    }, const <String, AgentStatusEntry>{});
    await pumpDebounce();

    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['removed'], isTrue);
  });

  test('batches burst updates into one request', () async {
    forwarder = AgentStatusHostForwarder(
      client: client,
      debounce: const Duration(milliseconds: 30),
    );
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1'),
    });
    forwarder.onStatusChanged(
      {'s1': _entry('s1')},
      {'s1': _entry('s1', state: .waiting)},
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final entries = sentEntries();
    // The later transition supersedes the earlier one for the same session.
    expect(entries, hasLength(1));
    expect(entries.single['state'], 'waiting');
  });

  test('retries transport errors without losing presence', () async {
    client.error = StateError('host gone');
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1', state: .waiting),
    });
    await pumpDebounce();
    expect(client.attempts, greaterThan(0));
    expect(client.requests, isEmpty);

    client.error = null;
    await pumpDebounce();

    expect(client.requests, hasLength(1));
    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['state'], 'waiting');
  });

  test('does not retry permanent orchestration capability errors', () async {
    client.error = StateError(
      'The running terminal host does not support orchestration. Restart Alera to replace the terminal host before using orchestration.',
    );
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1', state: .waiting),
    });
    await pumpDebounce();

    expect(client.attempts, 1);
    await pumpDebounce();
    expect(client.attempts, 1);
    expect(client.requests, isEmpty);

    client.error = null;
    client.emitRuntimeHostConnected();
    await pumpDebounce();

    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['state'], 'waiting');
  });

  test('drops stale retries after a newer state is delivered', () async {
    final waitingResult = Completer<Object?>();
    final workingResult = Completer<Object?>();
    client.queuedResults.addAll(<Completer<Object?>>[
      waitingResult,
      workingResult,
    ]);

    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1', state: .waiting),
    });
    await pumpDebounce();
    forwarder.onStatusChanged(
      {'s1': _entry('s1', state: .waiting)},
      {'s1': _entry('s1', state: .working)},
    );
    await pumpDebounce();

    workingResult.complete(null);
    await pumpDebounce();
    waitingResult.completeError(StateError('stale transport failure'));
    await pumpDebounce();

    expect(client.attempts, 2);
    expect(client.requests, hasLength(1));
    final entries = sentEntries();
    expect(entries.single['terminalSessionId'], 's1');
    expect(entries.single['state'], 'working');
  });

  test('does nothing after dispose', () async {
    forwarder.dispose();
    forwarder.onStatusChanged(const <String, AgentStatusEntry>{}, {
      's1': _entry('s1'),
    });
    await pumpDebounce();
    expect(client.requests, isEmpty);
  });
}
