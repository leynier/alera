import 'dart:async';

import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const result = <String, Object?>{
    'tab': <String, Object?>{'id': 'tab-1'},
    'agentType': 'codex',
    'profileId': 'profile-1',
  };

  test('uses the atomic idempotent launch verb', () async {
    final host = _FakeRuntimeHostClient((type, _) async => result);
    final client = PromptWorkspaceRuntimeClient(host);

    final launch = await client.launchAgent(
      workspaceId: 'workspace-1',
      profileId: 'profile-1',
      prompt: 'Build it',
      clientMutationId: 'mutation-1',
      requireIdempotency: false,
    );

    expect(host.requests, <String>['agentProfile.launchIdempotent']);
    expect(launch.idempotent, isTrue);
  });

  test('initial launch falls back only when the new verb is unknown', () async {
    final host = _FakeRuntimeHostClient((type, _) async {
      if (type == 'agentProfile.launchIdempotent') {
        throw StateError(
          'Unknown terminal host request: agentProfile.launchIdempotent',
        );
      }
      return result;
    });
    final client = PromptWorkspaceRuntimeClient(host);

    final launch = await client.launchAgent(
      workspaceId: 'workspace-1',
      profileId: 'profile-1',
      prompt: 'Build it',
      clientMutationId: 'mutation-1',
      requireIdempotency: false,
    );

    expect(host.requests, <String>[
      'agentProfile.launchIdempotent',
      'agentProfile.launch',
    ]);
    expect(launch.idempotent, isFalse);
  });

  test('retry never falls back to the legacy launch verb', () async {
    final error = StateError(
      'Unknown terminal host request: agentProfile.launchIdempotent',
    );
    final host = _FakeRuntimeHostClient((_, _) async => throw error);
    final client = PromptWorkspaceRuntimeClient(host);

    await expectLater(
      client.launchAgent(
        workspaceId: 'workspace-1',
        profileId: 'profile-1',
        prompt: 'Build it',
        clientMutationId: 'mutation-1',
        requireIdempotency: true,
      ),
      throwsA(same(error)),
    );
    expect(host.requests, <String>['agentProfile.launchIdempotent']);
  });

  test('transport failures never trigger a legacy launch', () async {
    final error = TimeoutException('response lost');
    final host = _FakeRuntimeHostClient((_, _) async => throw error);
    final client = PromptWorkspaceRuntimeClient(host);

    await expectLater(
      client.launchAgent(
        workspaceId: 'workspace-1',
        profileId: 'profile-1',
        prompt: 'Build it',
        clientMutationId: 'mutation-1',
        requireIdempotency: false,
      ),
      throwsA(same(error)),
    );
    expect(host.requests, <String>['agentProfile.launchIdempotent']);
  });

  test('a failed legacy fallback is marked non-idempotent', () async {
    final transportError = TimeoutException('legacy response lost');
    final host = _FakeRuntimeHostClient((type, _) async {
      if (type == 'agentProfile.launchIdempotent') {
        throw StateError(
          'Unknown terminal host request: agentProfile.launchIdempotent',
        );
      }
      throw transportError;
    });
    final client = PromptWorkspaceRuntimeClient(host);

    await expectLater(
      client.launchAgent(
        workspaceId: 'workspace-1',
        profileId: 'profile-1',
        prompt: 'Build it',
        clientMutationId: 'mutation-1',
        requireIdempotency: false,
      ),
      throwsA(
        isA<NonIdempotentAgentLaunchFailure>().having(
          (error) => error.cause,
          'cause',
          same(transportError),
        ),
      ),
    );
    expect(host.requests, <String>[
      'agentProfile.launchIdempotent',
      'agentProfile.launch',
    ]);
  });
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  _FakeRuntimeHostClient(this.handler);

  final Future<Object?> Function(String, Map<String, Object?>) handler;
  final List<String> requests = <String>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    requests.add(type);
    return handler(type, payload);
  }
}
