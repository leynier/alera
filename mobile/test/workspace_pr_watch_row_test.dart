import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/pull_requests/infra/mobile_runtime_pull_request_watch_requests.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a watch eye with the scope tooltip', (tester) async {
    const watch = MobilePullRequestWatch(
      workspaceId: 'workspace-1',
      reviewNumber: 801,
      mode: 'fixAndMerge',
      conflicts: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: MobileWorkspaceListRow(
            row: const MobileWorkspaceEntryRow(
              entry: WorkspaceTreeEntry(
                workspace: WorkspaceSummary(
                  id: 'workspace-1',
                  projectId: 'project-1',
                  name: 'Workspace',
                  path: '/repo',
                ),
                depth: 0,
                visibleChildCount: 0,
                childrenCollapsed: false,
              ),
            ),
            onTap: () {},
            onLongPress: () {},
            onMore: () {},
            onToggleChildren: () {},
            terminalTabCount: 0,
            agentsExpanded: false,
            onToggleAgents: () {},
            onAgentTap: (_) {},
            onCloseAgent: (_) {},
            pullRequestWatch: watch,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('workspace-tray-pr-watch')), findsOneWidget);
    expect(find.byIcon(AleraIcons.visible), findsOneWidget);
    expect(watch.tooltip, contains('Merge Conflicts: Off'));
    expect(watch.tooltip, contains('Watching: Fix and Merge'));
  });

  test('runtime mixin lists watches when the capability is present', () async {
    final client = _FakeRequests(<String>{pullRequestWatchCapability});
    expect(client.supportsPullRequestWatch, isTrue);
    final items = await client.listPullRequestWatches();
    expect(items, hasLength(1));
    expect(items.single.reviewNumber, 801);
    expect(_FakeRequests(const <String>{}).supportsPullRequestWatch, isFalse);
  });
}

class _FakeRequests with MobileRuntimePullRequestWatchRequests {
  _FakeRequests(this.runtimeCapabilities);

  @override
  final Set<String> runtimeCapabilities;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    expect(type, 'pullRequestWatch.list');
    return <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'workspaceId': 'workspace-1',
          'reviewNumber': 801,
          'mode': 'fix',
          'checks': true,
          'comments': true,
          'conflicts': true,
        },
      ],
    };
  }
}
