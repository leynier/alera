import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_agent_watch_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

MobilePullRequestSnapshot _snapshot({
  String mergeable = 'MERGEABLE',
  List<Map<String, Object?>> checks = const <Map<String, Object?>>[
    <String, Object?>{'name': 'build', 'bucket': 'pass'},
  ],
}) {
  return MobilePullRequestSnapshot.fromJson(<String, Object?>{
    'branch': 'feat/actions',
    'provider': 'github',
    'authStatus': 'authenticated',
    'mergeMethods': <String>['squash'],
    'review': <String, Object?>{
      'number': 700,
      'title': 'feat: mobile actions',
      'state': 'OPEN',
      'url': 'https://github.com/leynier/alera/pull/700',
      'mergeable': mergeable,
      'headSha': 'abc123',
      'checks': checks,
      'comments': <Object?>[],
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTerminalClient client;
  late ProviderContainer container;

  setUp(() {
    client = FakeTerminalClient()
      ..tabs = [fakeTab(id: 'tab-1', title: 'Codex')]
      ..pullRequestsSupported = true
      ..pullRequestActionsSupported = true
      ..pullRequest = _snapshot();
    container = ProviderContainer(
      overrides: [
        appLifecycleControllerProvider.overrideWithValue(
          AppLifecycleState.resumed,
        ),
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    container.listen(
      pullRequestAgentWatchControllerProvider('host-1', 'workspace-1'),
      (_, _) {},
    );
    container.listen(
      pullRequestActionControllerProvider('host-1', 'workspace-1'),
      (_, _) {},
    );
    container.listen(
      tabsControllerProvider('host-1', 'workspace-1'),
      (_, _) {},
    );
  });

  tearDown(() {
    container.dispose();
    return client.dispose();
  });

  PullRequestAgentWatchController watch() => container.read(
    pullRequestAgentWatchControllerProvider('host-1', 'workspace-1').notifier,
  );

  test('merges a green review as soon as watch starts', () async {
    watch().start(
      reviewNumber: 700,
      mode: PullRequestAgentWatchMode.fixAndMerge,
      binding: const AgentTaskDispatchBinding(profileId: 'profile-1'),
      snapshot: _snapshot(),
    );

    await _until(() => client.calls.any((call) => call.startsWith('merge')));
    expect(client.calls, contains('mergePullRequest 700 squash'));
  });

  test('reads the loaded panel when start omits the snapshot', () async {
    await container.read(
      pullRequestControllerProvider('host-1', 'workspace-1').future,
    );
    watch().start(
      reviewNumber: 700,
      mode: PullRequestAgentWatchMode.fixAndMerge,
      binding: const AgentTaskDispatchBinding(profileId: 'profile-1'),
    );

    await _until(() => client.calls.any((call) => call.startsWith('merge')));
    expect(client.calls, contains('mergePullRequest 700 squash'));
  });

  test('retries a failed inject on the snapshot already in hand', () async {
    await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );
    watch().start(
      reviewNumber: 700,
      mode: PullRequestAgentWatchMode.fix,
      binding: const AgentTaskDispatchBinding(tabId: 'tab-1'),
      snapshot: _snapshot(
        checks: const <Map<String, Object?>>[
          <String, Object?>{'name': 'build', 'bucket': 'fail'},
        ],
      ),
    );

    await _until(() => client.calls.any((call) => call.startsWith('write')));
    expect(
      client.calls.singleWhere((call) => call.startsWith('write')),
      contains('session-tab-1'),
    );
  });
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 40; i++) {
    if (done()) {
      return;
    }
    await Future<void>.value();
  }
  fail('timed out waiting for the watch action');
}
