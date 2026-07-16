import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs the resolved local sidecar with runtime-proxy', () async {
    final runner = _RecordingRunner();
    final client = RuntimeProxyClient(
      processRunner: runner,
      cliResolver: const _Resolver(),
      applicationSupportDirectory: () async => Directory('/tmp/alera'),
    );

    await client.request(
      hostId: 'local',
      target: null,
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
    );

    expect(runner.executable, '/opt/alera');
    expect(runner.arguments, <String>['--dev', 'runtime-proxy']);
    expect(runner.stdin, contains('"type":"agentQuota.fetch"'));
  });

  test('constructs a POSIX remote runtime command', () async {
    final runner = _RecordingRunner();
    final client = RuntimeProxyClient(processRunner: runner);

    await client.request(
      hostId: 'linux',
      target: _target(runtimePlatform: 'linux'),
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
    );

    expect(runner.executable, 'ssh');
    expect(runner.arguments, contains('leynier@example.test'));
    expect(
      runner.arguments!.last,
      contains(r'$HOME/.alera/runtime/current/alera'),
    );
    expect(runner.arguments!.last, contains('runtime-proxy'));
  });

  test('constructs a PowerShell remote runtime command', () async {
    final runner = _RecordingRunner();
    final client = RuntimeProxyClient(processRunner: runner);

    await client.request(
      hostId: 'windows',
      target: _target(runtimePlatform: 'windows'),
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
    );

    expect(runner.arguments!.last, contains('powershell -NoProfile'));
    expect(runner.arguments!.last, contains(r'current\alera.exe'));
    expect(runner.arguments!.last, contains('runtime-proxy'));
  });

  test('sends the independent Claude Default setting to the sidecar', () async {
    final runner = _RecordingRunner();
    final client = RuntimeProxyClient(
      processRunner: runner,
      cliResolver: const _Resolver(),
      applicationSupportDirectory: () async => Directory('/tmp/alera'),
    );
    final service = AgentQuotaService(client);

    await service.fetch(
      hostId: 'local',
      target: null,
      settings: const AgentQuotaHostSettings(
        enabledProviders: <AgentQuotaProviderId>[AgentQuotaProviderId.claude],
        claudeDefaultEnabled: false,
        claudeProfiles: <ClaudeQuotaProfileSettings>[
          ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'leynierdev'),
        ],
        environment: AgentQuotaEnvironmentSettings(
          kimiApiKey: 'CUSTOM_KIMI_KEY',
        ),
      ),
    );

    final request = jsonDecode(runner.stdin.trim()) as Map<String, Object?>;
    final payload = request['payload'] as Map<String, Object?>;
    expect(payload['claudeDefaultEnabled'], isFalse);
    expect(payload['claudeProfiles'], hasLength(1));
    final environmentNames =
        payload['environmentNames'] as Map<String, Object?>;
    expect(environmentNames['kimiApiKey'], 'CUSTOM_KIMI_KEY');
  });
}

SshTarget _target({required String runtimePlatform}) {
  final now = DateTime.utc(2026);
  return SshTarget(
    id: runtimePlatform,
    alias: runtimePlatform,
    host: 'example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.key,
    createdAt: now,
    updatedAt: now,
    runtimePlatform: runtimePlatform,
    bootstrapStatus: SshBootstrapStatus.installed,
  );
}

class _Resolver implements AleraCliResolver {
  const _Resolver();

  @override
  Future<AleraCliCommand> resolve({required String runtimeDir}) async {
    return const AleraCliCommand(
      executable: '/opt/alera',
      prefixArguments: <String>['--dev'],
    );
  }
}

class _RecordingRunner implements ProcessRunner {
  String? executable;
  List<String>? arguments;
  String stdin = '';

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    return StartedProcess(
      stdinWrite: (data) => stdin += utf8.decode(data),
      stdout: Stream<List<int>>.value(
        utf8.encode('{"id":1,"ok":true,"payload":{"snapshots":[]}}\n'),
      ),
      stderr: const Stream<List<int>>.empty(),
      pid: 1,
      exitCode: Future<int>.value(0),
      kill: ([signal]) => true,
    );
  }

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
