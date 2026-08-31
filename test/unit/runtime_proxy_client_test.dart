import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
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

  test(
    'hydrates missing shell credential variables for local requests',
    () async {
      final runner = _RecordingRunner();
      final resolver = _FakeEnvironmentResolver(<String, String>{
        'KIMI_API_KEY': 'secret-from-zshrc',
      });
      final client = RuntimeProxyClient(
        processRunner: runner,
        environmentResolver: resolver,
        platformEnvironment: const <String, String>{'PATH': '/usr/bin'},
        cliResolver: const _Resolver(),
        applicationSupportDirectory: () async => Directory('/tmp/alera'),
      );

      await client.request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
        localEnvironmentNames: const <String>['KIMI_API_KEY', 'ZAI_API_KEY'],
      );

      expect(resolver.requests, <List<String>>[
        <String>['KIMI_API_KEY', 'ZAI_API_KEY'],
      ]);
      expect(runner.environment, <String, String>{
        'KIMI_API_KEY': 'secret-from-zshrc',
      });
    },
  );

  test(
    'does not override variables already in the process environment',
    () async {
      final runner = _RecordingRunner();
      final resolver = _FakeEnvironmentResolver(<String, String>{
        'KIMI_API_KEY': 'stale-from-zshrc',
      });
      final client = RuntimeProxyClient(
        processRunner: runner,
        environmentResolver: resolver,
        platformEnvironment: const <String, String>{
          'KIMI_API_KEY': 'from-process',
        },
        cliResolver: const _Resolver(),
        applicationSupportDirectory: () async => Directory('/tmp/alera'),
      );

      await client.request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
        localEnvironmentNames: const <String>['KIMI_API_KEY'],
      );

      expect(resolver.requests, isEmpty);
      expect(runner.environment, isNull);
    },
  );

  test('remote requests never consult the environment resolver', () async {
    final runner = _RecordingRunner();
    final resolver = _FakeEnvironmentResolver(<String, String>{
      'KIMI_API_KEY': 'secret-from-zshrc',
    });
    final client = RuntimeProxyClient(
      processRunner: runner,
      environmentResolver: resolver,
      platformEnvironment: const <String, String>{},
    );

    await client.request(
      hostId: 'linux',
      target: _target(runtimePlatform: 'linux'),
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
      localEnvironmentNames: const <String>['KIMI_API_KEY'],
    );

    expect(resolver.requests, isEmpty);
    expect(runner.environment, isNull);
  });

  test('fetch requests hydration for the configured variable names', () async {
    final runner = _RecordingRunner();
    final resolver = _FakeEnvironmentResolver(const <String, String>{});
    final client = RuntimeProxyClient(
      processRunner: runner,
      environmentResolver: resolver,
      platformEnvironment: const <String, String>{},
      cliResolver: const _Resolver(),
      applicationSupportDirectory: () async => Directory('/tmp/alera'),
    );
    final service = AgentQuotaService(client);

    await service.fetch(
      hostId: 'local',
      target: null,
      settings: const AgentQuotaHostSettings(
        enabledProviders: <AgentQuotaProviderId>[AgentQuotaProviderId.kimi],
        environment: AgentQuotaEnvironmentSettings(
          kimiApiKey: 'CUSTOM_KIMI_KEY',
        ),
      ),
    );

    expect(resolver.requests.single, contains('CUSTOM_KIMI_KEY'));
  });

  test('local quota fetches use the runtime host service', () async {
    final runner = _RecordingRunner();
    final runtime = _RecordingRuntimeHostClient();
    final service = AgentQuotaService(
      RuntimeProxyClient(processRunner: runner),
      runtime,
    );

    await service.fetch(hostId: 'local', target: null, settings: .defaults);

    expect(runtime.requests, <String>['agentQuota.snapshot']);
    expect(runtime.payloads.single['forceRefresh'], isFalse);
    expect(runtime.timeouts.single, const Duration(seconds: 45));
    expect(runner.executable, isNull);
  });

  test('local runtime quota fetch forwards missing shell variables', () async {
    final runtime = _RecordingRuntimeHostClient();
    final resolver = _FakeEnvironmentResolver(<String, String>{
      'CUSTOM_KIMI_KEY': 'secret-from-zshrc',
    });
    final service = AgentQuotaService(
      RuntimeProxyClient(
        processRunner: _RecordingRunner(),
        environmentResolver: resolver,
        platformEnvironment: const <String, String>{},
      ),
      runtime,
    );

    await service.fetch(
      hostId: 'local',
      target: null,
      settings: const AgentQuotaHostSettings(
        enabledProviders: <AgentQuotaProviderId>[AgentQuotaProviderId.kimi],
        environment: AgentQuotaEnvironmentSettings(
          kimiApiKey: 'CUSTOM_KIMI_KEY',
        ),
      ),
    );

    expect(runtime.payloads.single['environmentValues'], <String, String>{
      'CUSTOM_KIMI_KEY': 'secret-from-zshrc',
    });
  });

  test('manual quota refresh is consumed once for its host', () {
    final service = AgentQuotaService(
      RuntimeProxyClient(processRunner: _RecordingRunner()),
    );

    service.requestForceRefresh('local');

    expect(service.consumeForceRefresh('local'), isTrue);
    expect(service.consumeForceRefresh('local'), isFalse);
    expect(service.consumeForceRefresh('remote'), isFalse);
  });

  test('manual local quota fetch bypasses the runtime host cache', () async {
    final runtime = _RecordingRuntimeHostClient();
    final service = AgentQuotaService(
      RuntimeProxyClient(processRunner: _RecordingRunner()),
      runtime,
    );

    await service.fetch(
      hostId: 'local',
      target: null,
      settings: .defaults,
      forceRefresh: true,
    );

    expect(runtime.payloads.single['forceRefresh'], isTrue);
  });

  test('claude TUI fetch uses the dedicated runtime request', () async {
    final runtime = _RecordingRuntimeHostClient(
      responses: <String, Map<String, Object?>>{
        'agentQuota.fetchClaudeTui': <String, Object?>{
          'snapshot': <String, Object?>{
            'provider': 'claude',
            'accountId': 'partsbase',
            'displayName': 'Partsbase',
            'status': 'ok',
            'updatedAt': 1,
            'windows': <Object?>[],
            'buckets': <Object?>[],
          },
        },
      },
    );
    final service = AgentQuotaService(
      RuntimeProxyClient(processRunner: _RecordingRunner()),
      runtime,
    );

    final snapshot = await service.fetchClaudeTui(
      hostId: 'local',
      target: null,
      accountId: 'partsbase',
      displayName: 'Partsbase',
    );

    expect(runtime.requests, <String>['agentQuota.fetchClaudeTui']);
    expect(runtime.payloads.single['accountId'], 'partsbase');
    expect(runtime.timeouts.single, const Duration(seconds: 60));
    expect(snapshot.accountId, 'partsbase');
    expect(snapshot.status, AgentQuotaStatus.ok);
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
    expect(payload['allowCliFallback'], isFalse);
    expect(payload['claudeProfiles'], hasLength(1));
    final environmentNames =
        payload['environmentNames'] as Map<String, Object?>;
    expect(environmentNames['kimiApiKey'], 'CUSTOM_KIMI_KEY');
  });

  test('proxy quota fetch never enables Claude CLI fallback', () async {
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
      settings: .defaults,
      forceRefresh: true,
    );

    final request = jsonDecode(runner.stdin.trim()) as Map<String, Object?>;
    final payload = request['payload'] as Map<String, Object?>;
    expect(payload['allowCliFallback'], isFalse);
  });
}

class _FakeEnvironmentResolver(final Map<String, String> values)
    implements CommandEnvironmentResolver {
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<Map<String, String>> environment() async => values;

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async {
    requests.add(List<String>.of(names));
    return <String, String>{
      for (final name in names)
        if (values.containsKey(name)) name: values[name]!,
    };
  }
}

class _RecordingRuntimeHostClient({
  final Map<String, Map<String, Object?>> responses =
      const <String, Map<String, Object?>>{},
}) implements RuntimeHostClient {
  final List<String> requests = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Duration?> timeouts = <Duration?>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(type);
    payloads.add(payload);
    timeouts.add(timeout);
    return responses[type] ?? <String, Object?>{'snapshots': <Object?>[]};
  }
}

SshTarget _target({required String runtimePlatform}) {
  final now = DateTime.utc(2026);
  return SshTarget(
    id: runtimePlatform,
    alias: runtimePlatform,
    host: 'example.test',
    port: 22,
    username: 'leynier',
    authKind: .key,
    createdAt: now,
    updatedAt: now,
    runtimePlatform: runtimePlatform,
    bootstrapStatus: .installed,
  );
}

class const _Resolver() implements AleraCliResolver {
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
  Map<String, String>? environment;
  String stdin = '';

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.environment = environment;
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
