import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_request_watch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/pull_request_agent_watch_fixtures.dart';

void main() {
  testWidgets('hides when no watch is running', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pullRequestAgentWatchControllerProvider.overrideWith(
            _EmptyWatchController.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WorkspacePullRequestWatchIndicator(workspaceId: 'w'),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('workspace-tray-pr-watch')), findsNothing);
  });

  testWidgets('shows the eye and a config tooltip', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pullRequestAgentWatchControllerProvider.overrideWith(
            _WatchController.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WorkspacePullRequestWatchIndicator(workspaceId: 'w'),
          ),
        ),
      ),
    );
    expect(find.byIcon(AleraIcons.visible), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('Merge Conflicts: Off'),
    );
  });
}

class _EmptyWatchController extends PullRequestAgentWatchController {
  @override
  Map<String, PullRequestAgentWatchSession> build() {
    return const <String, PullRequestAgentWatchSession>{};
  }
}

class _WatchController extends PullRequestAgentWatchController {
  @override
  Map<String, PullRequestAgentWatchSession> build() {
    return const <String, PullRequestAgentWatchSession>{
      'w': PullRequestAgentWatchSession(
        workspaceId: 'w',
        reviewNumber: 801,
        mode: .fixAndMerge,
        binding: AgentTaskDispatchBinding(tabId: 'tab-1'),
        scope: pullRequestWatchTestScope,
        watchScope: PullRequestAgentWatchScope(conflicts: false),
      ),
    };
  }
}
