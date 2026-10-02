import 'dart:async';

import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

void main() {
  test(
    'does not let an older host response overwrite the quota cache',
    () async {
      final runtime = _QueuedQuotaRuntimeHostClient();
      final service = AgentQuotaService(
        RuntimeProxyClient(
          processRunner: FakeRecordingProcessRunner(<Object>[]),
        ),
        runtime,
      );
      final first = service.fetch(
        hostId: 'local',
        target: null,
        settings: .defaults,
      );
      await Future<void>.delayed(Duration.zero);
      final second = service.fetch(
        hostId: 'local',
        target: null,
        settings: .defaults,
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.pending, hasLength(2));

      runtime.pending[1].complete(_quotaPayload('new-account'));
      await second;
      runtime.pending[0].complete(_quotaPayload('old-account'));
      await first;

      final failed = service.fetch(
        hostId: 'local',
        target: null,
        settings: .defaults,
      );
      await Future<void>.delayed(Duration.zero);
      runtime.pending[2].completeError(StateError('host unavailable'));
      final recovered = await failed;

      expect(recovered.snapshots.single.accountId, 'new-account');
    },
  );

  test(
    'does not let an older Claude TUI response overwrite the cache',
    () async {
      final runtime = _QueuedQuotaRuntimeHostClient();
      final service = _service(runtime);
      final tui = service.fetchClaudeTui(
        hostId: 'local',
        target: null,
        accountId: 'old-account',
      );
      await Future<void>.delayed(Duration.zero);
      final fetch = service.fetch(
        hostId: 'local',
        target: null,
        settings: .defaults,
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.requests, <String>[
        'agentQuota.fetchClaudeTui',
        'agentQuota.snapshot',
      ]);

      runtime.pending[1].complete(_quotaPayload('new-account'));
      await fetch;
      runtime.pending[0].complete(_claudeTuiPayload('old-account'));
      await tui;

      final recovered = await _readCachedState(service, runtime);
      expect(recovered.snapshots.single.accountId, 'new-account');
    },
  );

  test('does not let an older reset response overwrite the cache', () async {
    final runtime = _QueuedQuotaRuntimeHostClient();
    final service = _service(runtime);
    final consume = service.consumeCodexResetCredit(
      hostId: 'local',
      target: null,
      offerRevision: 'old-revision',
    );
    await Future<void>.delayed(Duration.zero);
    final fetch = service.fetch(
      hostId: 'local',
      target: null,
      settings: .defaults,
    );
    await Future<void>.delayed(Duration.zero);
    expect(runtime.requests, <String>[
      'agentQuota.consumeCodexResetCredit',
      'agentQuota.snapshot',
    ]);

    runtime.pending[1].complete(
      _quotaPayload('default', provider: 'codex', displayName: 'fresh'),
    );
    await fetch;
    runtime.pending[0].complete(_consumePayload('stale'));
    await consume;

    final recovered = await _readCachedState(service, runtime);
    expect(recovered.snapshots.single.displayName, 'fresh');
  });
}

AgentQuotaService _service(_QueuedQuotaRuntimeHostClient runtime) {
  return AgentQuotaService(
    RuntimeProxyClient(processRunner: FakeRecordingProcessRunner(<Object>[])),
    runtime,
  );
}

Future<AgentQuotaState> _readCachedState(
  AgentQuotaService service,
  _QueuedQuotaRuntimeHostClient runtime,
) async {
  final failed = service.fetch(
    hostId: 'local',
    target: null,
    settings: .defaults,
  );
  await Future<void>.delayed(Duration.zero);
  runtime.pending.last.completeError(StateError('host unavailable'));
  return failed;
}

Map<String, Object?> _quotaPayload(
  String accountId, {
  String provider = 'claude',
  String? displayName,
}) => <String, Object?>{
  'snapshots': <Object?>[
    <String, Object?>{
      'provider': provider,
      'accountId': accountId,
      'displayName': ?displayName,
      'status': 'ok',
      'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    },
  ],
  'environment': const <String, bool>{},
};

Map<String, Object?> _claudeTuiPayload(String accountId) => <String, Object?>{
  'snapshot': <String, Object?>{
    'provider': 'claude',
    'accountId': accountId,
    'status': 'ok',
    'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
  },
};

Map<String, Object?> _consumePayload(String displayName) => <String, Object?>{
  'status': 'consumed',
  'outcome': 'reset',
  'snapshot': <String, Object?>{
    'provider': 'codex',
    'accountId': 'default',
    'displayName': displayName,
    'status': 'ok',
  },
};

final class _QueuedQuotaRuntimeHostClient implements RuntimeHostClient {
  final List<Completer<Object?>> pending = <Completer<Object?>>[];
  final List<String> requests = <String>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    requests.add(type);
    final completer = Completer<Object?>();
    pending.add(completer);
    return completer.future;
  }
}
