import 'dart:async';

import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

import 'package:alera/src/features/pull_requests/infra/runtime_pull_request_watch_repository.dart';

import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _scope = WorkspacePullRequestScope(workspaceId: 'w', repoPath: '/repo');

class _Workbench extends WorkbenchController {
  @override
  WorkbenchState build() => WorkbenchState(
    activeWorkspaceId: 'other',
    workspacesByProject: {
      'p': [
        Workspace(
          id: 'w',
          projectId: 'p',
          name: 'Work',
          path: '/repo',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          kind: .linked,
          status: .active,
        ),
      ],
    },
  );
}

class _Panel extends WorkspacePullRequestController {
  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async => const WorkspacePullRequestState(
    review: HostedReview(
      provider: .github,
      number: 42,
      title: 'PR',
      state: .open,
      url: 'https://github.com/o/r/pull/42',
      headSha: 'abc',
    ),
  );
  @override
  void attachWatcher() {}
  @override
  void detachWatcher() {}
}

class _Runtime implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final events = StreamController<RuntimeHostEvent>.broadcast();
  Map<String, Object?>? watch;
  int starts = 0;
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;
  @override
  Future<bool> supportsRuntimeCapability(String capability) async => true;
  void changed() =>
      events.add(const RuntimeHostEvent('pullRequestWatchChanged', {}));
  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    switch (type) {
      case 'pullRequestWatch.list':
        return {
          'items': [?watch],
        };
      case 'pullRequestWatch.start':
        starts++;
        watch = payload;
        changed();
        return watch;
      case 'pullRequestWatch.stop':
        watch = null;
        changed();
        return {'removed': true};
      default:
        throw StateError('Unexpected local action: $type');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('desktop restores mobile watch, follows changes and stops through runtime without navigation', () async {
    final runtime = _Runtime()
      ..watch = {
        'workspaceId': 'w',
        'reviewNumber': 42,
        'mode': 'fixAndMerge',
        'tabId': 'mobile-agent',
        'checks': true,
        'comments': false,
        'conflicts': true,
      };
    final container = ProviderContainer(
      overrides: [
        pullRequestAgentWatchRepositoryProvider.overrideWithValue(
          RuntimePullRequestWatchRepository(
            runtime,
            coalescer: RuntimeChangeCoalescer(
              debounce: Duration.zero,
              maxDelay: Duration.zero,
            ),
          ),
        ),
        workbenchControllerProvider.overrideWith(_Workbench.new),
        effectiveHostingProviderOverrideProvider('p')
            .overrideWith((ref) async => null),
        workspacePullRequestControllerProvider(_scope).overrideWith(_Panel.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await runtime.events.close();
    });
    final watchProvider = pullRequestAgentWatchControllerProvider;
    container.listen(watchProvider, (_, _) {});
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future.pause(Duration.zero);
      }
    }

    await settle();
    expect(container.read(watchProvider)['w']?.mode.name, 'fixAndMerge');
    expect(container.read(watchProvider)['w']?.watchScope.comments, isFalse);
    runtime.watch = {
      ...runtime.watch!,
      'mode': 'fix',
      'tabId': 'changed-agent',
    };
    runtime.changed();
    await settle();
    expect(container.read(watchProvider)['w']?.binding.tabId, 'changed-agent');
    expect(container.read(watchProvider)['w']?.mode.name, 'fix');
    await container.read(watchProvider.notifier).stop('w');
    await settle();
    expect(container.read(watchProvider), isEmpty);
    await container
        .read(watchProvider.notifier)
        .start(
          scope: _scope,
          reviewNumber: 42,
          mode: .fixAndMerge,
          binding: const AgentTaskDispatchBinding(tabId: 'desktop-agent'),
        );
    await settle();
    expect(runtime.starts, 1);
    expect(container.read(watchProvider)['w']?.binding.tabId, 'desktop-agent');
    expect(
      container.read(workbenchControllerProvider).activeWorkspaceId,
      'other',
    );
    for (final provider in GitHostingProvider.values) {
      container
          .read(watchProvider.notifier)
          .onPanelState(
            'w',
            WorkspacePullRequestState(
              identity: GitRemoteIdentity(
                provider: provider,
                host: 'forge.example',
                owner: 'owner',
                repo: 'repo',
              ),
            ),
          );
      await settle();
      if (provider == GitHostingProvider.github) {
        expect(container.read(watchProvider)['w'], isNotNull);
      } else {
        expect(
          container.read(watchProvider),
          isEmpty,
          reason: '${provider.name} must stop when its review disappears',
        );
        expect(runtime.watch, isNull);
        await container
            .read(watchProvider.notifier)
            .start(
              scope: _scope,
              reviewNumber: 42,
              mode: .fixAndMerge,
              binding: const AgentTaskDispatchBinding(tabId: 'desktop-agent'),
            );
        await settle();
      }
    }
    runtime.watch = null;
    runtime.changed();
    await settle();
    expect(container.read(watchProvider), isEmpty);
  });
}
