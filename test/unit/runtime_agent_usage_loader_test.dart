import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_loader.dart';
import 'package:alera/src/features/agent_usage/infra/runtime_agent_usage_loader.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'remote usage sends only selected CCS profiles with Usage names',
    () async {
      final proxy = _RecordingRuntimeProxyClient();
      final loader = RuntimeAgentUsageLoader(_UnusedRuntimeHostClient(), proxy);

      await loader.fetch(
        AgentUsageRequest(
          hostId: 'remote-dev',
          target: null,
          settings: const AgentQuotaHostSettings(
            claudeDefaultEnabled: true,
            claudeDefaultShowInUsage: false,
            claudeProfiles: <ClaudeQuotaProfileSettings>[
              ClaudeQuotaProfileSettings(
                alias: 'ccdev',
                profile: 'dev',
                usageDisplayName: 'Engineering',
              ),
              ClaudeQuotaProfileSettings(
                alias: 'ccshared',
                profile: 'shared',
                showInUsage: false,
              ),
            ],
          ),
          sinceDay: '2026-08-04',
          untilDay: '2026-08-10',
        ),
      );

      expect(proxy.type, 'agentUsage.fetch');
      expect(proxy.payload['claudeDefaultEnabled'], isFalse);
      expect(proxy.payload['claudeProfiles'], <Object?>[
        <String, String>{'alias': 'Engineering', 'profile': 'dev'},
      ]);
    },
  );
}

class _UnusedRuntimeHostClient implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    throw UnsupportedError('Local runtime is not used by this test.');
  }
}

class _RecordingRuntimeProxyClient implements RuntimeProxyClient {
  String? type;
  Map<String, Object?> payload = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> request({
    required String hostId,
    required SshTarget? target,
    required String type,
    required Map<String, Object?> payload,
    List<String> localEnvironmentNames = const <String>[],
    Duration timeout = const Duration(seconds: 35),
  }) async {
    this.type = type;
    this.payload = payload;
    return <String, Object?>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
