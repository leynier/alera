import 'dart:async';

import 'package:alera/src/features/pull_requests/infra/runtime_pull_request_watch_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _Runtime implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _Runtime(this.capabilities);

  final Set<String> capabilities;
  final requests = <(String, Map<String, Object?>)>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    requests.add((type, payload));
    return <String, Object?>{'prompt': 'Runtime prompt for ${payload['kind']}'};
  }
}

void main() {
  test('V2 runtimes own every forge, V1 runtimes only GitHub', () async {
    final v1 = RuntimePullRequestWatchRepository(
      _Runtime({'pullRequestWatchExecutionV1'}),
    );
    final v2 = RuntimePullRequestWatchRepository(
      _Runtime({'pullRequestWatchExecutionV1', 'pullRequestWatchExecutionV2'}),
    );
    final legacy = RuntimePullRequestWatchRepository(_Runtime({}));
    for (final provider in GitHostingProvider.values) {
      expect(await v2.ownsExecutionFor(provider), isTrue);
      expect(
        await v1.ownsExecutionFor(provider),
        provider == GitHostingProvider.github,
      );
      expect(await legacy.ownsExecutionFor(provider), isFalse);
    }
    expect(await v2.ownsExecutionFor(null), isFalse);
  });

  test(
    'dispatch prompts come from the runtime only when it owns them',
    () async {
      final runtime = _Runtime({'pullRequestAgentDispatchV1'});
      final prompt = await RuntimePullRequestWatchRepository(runtime)
          .agentDispatchPrompt(
            workspaceId: 'w',
            kind: 'fixFailedChecks',
            reviewNumber: 7,
          );
      expect(prompt, 'Runtime prompt for fixFailedChecks');
      expect(runtime.requests.single.$1, 'pullRequest.agentDispatch');
      expect(runtime.requests.single.$2, <String, Object?>{
        'workspaceId': 'w',
        'kind': 'fixFailedChecks',
        'number': 7,
      });
      final older = _Runtime({});
      expect(
        await RuntimePullRequestWatchRepository(older)
            .agentDispatchPrompt(workspaceId: 'w', kind: 'restack'),
        isNull,
      );
      expect(older.requests, isEmpty);
    },
  );
}
