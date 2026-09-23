import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/pull_requests/application/pull_request_watch_controller.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

class _Runtime extends FakeTerminalClient
    implements MobilePullRequestWatchExecutionClient {
  Map<String, Object?>? watch;
  bool reject = false;
  int starts = 0;
  int stops = 0;
  @override
  bool get supportsPullRequestWatch => true;
  @override
  bool get supportsPullRequestWatchExecution => true;
  @override
  Future<List<MobilePullRequestWatch>> listPullRequestWatches() async => [
    if (watch != null) MobilePullRequestWatch.fromJson(watch!),
  ];
  @override
  Future<void> startPullRequestWatch(Map<String, Object?> value) async {
    starts++;
    if (reject) throw StateError('offline');
    watch = value;
    emitEvent('pullRequestWatchChanged');
  }

  @override
  Future<void> stopPullRequestWatch(String workspaceId) async {
    stops++;
    if (reject) throw StateError('offline');
    watch = null;
    emitEvent('pullRequestWatchChanged');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final panel = pullRequestAgentWatchControllerProvider('host', 'workspace');
  final rows = pullRequestWatchControllerProvider('host');
  late _Runtime runtime;
  late ProviderContainer container;
  setUp(() {
    runtime = _Runtime();
    container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host').overrideWith((ref) async => runtime),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await runtime.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future.pause(Duration.zero);
    }
  }

  test('mobile activation shares runtime state with rows and never dispatches locally', () async {
    container.listen(panel, (_, _) {});
    await container.read(rows.future);
    await container
        .read(panel.notifier)
        .start(
          reviewNumber: 42,
          mode: PullRequestAgentWatchMode.fixAndMerge,
          binding: const AgentTaskDispatchBinding(
            tabId: 'agent',
            profileId: 'profile',
          ),
          watchScope: const PullRequestAgentWatchScope(
            checks: true,
            comments: false,
            conflicts: true,
          ),
        );
    await settle();
    expect(runtime.starts, 1);
    expect(runtime.watch?['profileId'], 'profile');
    expect(container.read(rows).value!.byWorkspace['workspace']!.merge, isTrue);
    expect(container.read(panel)?.mode, PullRequestAgentWatchMode.fixAndMerge);
    expect(container.read(panel)?.watchScope.comments, isFalse);
    expect(runtime.calls, isEmpty);
    await container.read(panel.notifier).stop();
    await settle();
    expect(runtime.stops, 1);
    expect(container.read(rows).value!.byWorkspace, isEmpty);
    expect(container.read(panel), isNull);
  });

  test(
    'opening the panel after the rows loaded restores a desktop watch',
    () async {
      runtime.watch = {
        'workspaceId': 'workspace',
        'reviewNumber': 42,
        'mode': 'fix',
        'tabId': 'desktop-agent',
      };
      container.listen(rows, (_, _) {});
      await container.read(rows.future);
      container.listen(panel, (_, _) {});
      expect(container.read(panel)?.binding.tabId, 'desktop-agent');
      runtime.watch = {...runtime.watch!, 'mode': 'fixAndMerge'};
      runtime.emitEvent('pullRequestWatchChanged');
      await settle();
      expect(
        container.read(panel)?.mode,
        PullRequestAgentWatchMode.fixAndMerge,
      );
      runtime.watch = null;
      runtime.emitEvent('pullRequestWatchChanged');
      await settle();
      expect(container.read(panel), isNull);
      expect(container.read(rows).value!.byWorkspace, isEmpty);
      expect(runtime.starts, 0);
    },
  );

  test(
    'failed activation does not publish a local eye or start polling',
    () async {
      runtime.reject = true;
      container.listen(panel, (_, _) {});
      await expectLater(
        container
            .read(panel.notifier)
            .start(
              reviewNumber: 42,
              mode: PullRequestAgentWatchMode.fix,
              binding: const AgentTaskDispatchBinding(tabId: 'agent'),
            ),
        throwsStateError,
      );
      await settle();
      expect(container.read(panel), isNull);
      expect(container.read(rows).value!.byWorkspace, isEmpty);
      expect(runtime.calls, isEmpty);
    },
  );

  test('failed stop preserves the authoritative active watch', () async {
    runtime.watch = {
      'workspaceId': 'workspace',
      'reviewNumber': 42,
      'mode': 'fix',
      'tabId': 'agent',
    };
    container.listen(panel, (_, _) {});
    await container.read(rows.future);
    await settle();
    runtime.reject = true;
    await expectLater(container.read(panel.notifier).stop(), throwsStateError);
    expect(container.read(panel), isNotNull);
    expect(container.read(rows).value!.byWorkspace, isNotEmpty);
  });
}
