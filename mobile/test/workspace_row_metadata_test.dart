import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_pull_request_status_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('main workspace shows the project folder glyph', (tester) async {
    await tester.pumpWidget(_rowApp(kind: 'main'));

    expect(find.byIcon(AleraIcons.workspaceMain), findsOneWidget);
    expect(find.byTooltip('Project folder'), findsOneWidget);
    expect(find.byType(AleraLinkedWorktreeIcon), findsNothing);
    expect(find.byTooltip('Linked worktree'), findsNothing);
  });

  testWidgets('linked workspace shows the sideways branch glyph', (
    tester,
  ) async {
    await tester.pumpWidget(_rowApp(kind: 'linked'));

    expect(find.byType(AleraLinkedWorktreeIcon), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(
      tester
          .widget<RotatedBox>(
            find.descendant(
              of: find.byType(AleraLinkedWorktreeIcon),
              matching: find.byType(RotatedBox),
            ),
          )
          .quarterTurns,
      AleraLinkedWorktreeIcon.quarterTurns,
    );
    expect(find.byTooltip('Linked worktree'), findsOneWidget);
    expect(find.byIcon(AleraIcons.workspaceMain), findsNothing);
    expect(find.byTooltip('Project folder'), findsNothing);
  });

  testWidgets('a pull request summary adds the status indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(
        summary: MobileWorkspacePullRequestSummary(
          workspaceId: 'workspace-1',
          number: 12,
          title: 'Add fork indicators',
          state: MobileWorkspacePullRequestState.open,
          mergeable: MobileWorkspacePullRequestMergeable.mergeable,
          checksRollup: MobileWorkspacePullRequestChecksRollup.pending,
          pendingCheckCount: 2,
        ),
      ),
    );

    expect(find.byType(MobileWorkspacePullRequestStatusIcon), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitPullRequest), findsOneWidget);
    expect(find.byIcon(AleraIcons.loading), findsOneWidget);
  });

  testWidgets('rows without a pull request omit the indicator', (tester) async {
    await tester.pumpWidget(_rowApp());

    expect(find.byType(MobileWorkspacePullRequestStatusIcon), findsNothing);
  });

  testWidgets(
    'a linked review and an active watch stay visible on a narrow row',
    (tester) async {
      await tester.pumpWidget(
        _rowApp(
          summary: MobileWorkspacePullRequestSummary(
            workspaceId: 'workspace-1',
            number: 12,
            title: 'Add fork indicators',
            state: MobileWorkspacePullRequestState.open,
            mergeable: MobileWorkspacePullRequestMergeable.mergeable,
            checksRollup: MobileWorkspacePullRequestChecksRollup.pending,
            pendingCheckCount: 2,
          ),
          watch: const MobilePullRequestWatch(
            workspaceId: 'workspace-1',
            reviewNumber: 12,
            mode: 'fix',
          ),
          width: 320,
        ),
      );

      expect(
        find.byKey(const Key('workspace-tray-pull-request')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('workspace-tray-pr-watch')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _rowApp({
  String kind = 'linked',
  MobileWorkspacePullRequestSummary? summary,
  MobilePullRequestWatch? watch,
  double? width,
}) {
  return MaterialApp(
    theme: buildAleraMobileDarkTheme(),
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: MobileWorkspaceListRow(
          row: MobileWorkspaceEntryRow(
            entry: WorkspaceTreeEntry(
              workspace: WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project-1',
                name: 'Workspace',
                path: '/repo',
                kind: kind,
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
          terminalTabCount: 1,
          agentsExpanded: false,
          onToggleAgents: () {},
          onAgentTap: (_) {},
          onCloseAgent: (_) {},
          pullRequestSummary: summary,
          pullRequestWatch: watch,
        ),
      ),
    ),
  );
}
