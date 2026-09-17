import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_diff_viewer_screen.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/source_control_fixtures.dart';

const MobileGitDiffFile _diff = MobileGitDiffFile(
  path: 'lib/main.dart',
  area: 'unstaged',
  lines: <MobileGitDiffLine>[
    MobileGitDiffLine(kind: 'hunk', text: '@@ -10,2 +12,3 @@ class Foo'),
    MobileGitDiffLine(kind: 'context', text: ' void start() {'),
    MobileGitDiffLine(kind: 'deletion', text: '-  old();'),
    MobileGitDiffLine(kind: 'addition', text: '+  next();'),
  ],
);

void main() {
  testWidgets('long-press queues a diff line comment and keeps file comments', (
    tester,
  ) async {
    final client = sourceControlClient(
      writableSnapshot(entries: <MobileGitChange>[unstagedChange()]),
    )..gitDiffFile = _diff;
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: WorkspaceDiffViewerScreen(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            change: unstagedChange(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceDiffViewerScreen)),
    );
    container
        .read(
          workspaceAgentCommentControllerProvider(
            'host-1',
            'workspace-1',
          ).notifier,
        )
        .add(path: 'readme.md', body: 'Fix the typo');
    await tester.pump();
    expect(find.text('1 comment'), findsOneWidget);

    await tester.longPress(find.text('+  next();'));
    await tester.pumpAndSettle();
    expect(find.text('Comment on Diff'), findsOneWidget);
    expect(find.textContaining('old line'), findsNothing);
    expect(find.textContaining('line 13'), findsOneWidget);
    expect(find.text('+  next();'), findsWidgets);

    await tester.enterText(
      find.byType(TextField),
      'This addition looks wrong.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Comment'));
    await tester.pumpAndSettle();

    expect(find.text('2 comments'), findsOneWidget);
    expect(find.textContaining('readme.md: Fix the typo'), findsOneWidget);
    expect(find.textContaining('This addition looks wrong.'), findsOneWidget);
    expect(
      container.read(
        workspaceAgentCommentControllerProvider('host-1', 'workspace-1'),
      ),
      hasLength(2),
    );
    expect(
      container
          .read(
            workspaceAgentCommentControllerProvider('host-1', 'workspace-1'),
          )
          .last
          .kind,
      WorkspaceAgentCommentKind.diff,
    );
  });

  testWidgets('long-press on a deletion uses the old-side line label', (
    tester,
  ) async {
    final client = sourceControlClient(
      writableSnapshot(entries: <MobileGitChange>[unstagedChange()]),
    )..gitDiffFile = _diff;
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: WorkspaceDiffViewerScreen(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            change: unstagedChange(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('-  old();'));
    await tester.pumpAndSettle();
    expect(find.text('Comment on Diff'), findsOneWidget);
    expect(find.textContaining('old line 11'), findsOneWidget);
    expect(find.text('-  old();'), findsWidgets);
  });

  testWidgets('long-press on a hunk queues the hunk range', (tester) async {
    final client = sourceControlClient(
      writableSnapshot(entries: <MobileGitChange>[unstagedChange()]),
    )..gitDiffFile = _diff;
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: WorkspaceDiffViewerScreen(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            change: unstagedChange(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('@@ -10,2 +12,3 @@ class Foo'));
    await tester.pumpAndSettle();
    expect(find.text('Comment on Diff'), findsOneWidget);
    expect(find.textContaining('lines 12-14'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rewrite this hunk.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Comment'));
    await tester.pumpAndSettle();

    expect(find.text('1 comment'), findsOneWidget);
    expect(find.textContaining('Rewrite this hunk.'), findsOneWidget);
  });

  testWidgets('Open after send pops the diff and reveals the agent tab', (
    tester,
  ) async {
    final opened = <String>[];
    final client =
        sourceControlClient(
            writableSnapshot(entries: <MobileGitChange>[unstagedChange()]),
          )
          ..gitDiffFile = _diff
          ..agentProfiles = const <AgentProfileSummary>[
            AgentProfileSummary(
              id: 'profile-1',
              name: 'Codex',
              agentType: 'codex',
              showInNewTabMenu: true,
            ),
          ];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(agentPresenceControllerProvider('host-1'));
              ref.watch(tabsControllerProvider('host-1', 'workspace-1'));
              return _PushedDiffHome(onOpenTab: opened.add);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Diff'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceDiffViewerScreen)),
    );
    container
        .read(
          workspaceAgentCommentControllerProvider(
            'host-1',
            'workspace-1',
          ).notifier,
        )
        .add(path: 'lib/main.dart', body: 'Rename x');
    await tester.pump();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceDiffViewerScreen), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceDiffViewerScreen), findsNothing);
    expect(find.text('Show Diff'), findsOneWidget);
    expect(opened, <String>['agent-tab']);
  });
}

class const _PushedDiffHome({required final ValueChanged<String> onOpenTab})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => WorkspaceDiffViewerScreen(
                hostId: 'host-1',
                workspaceId: 'workspace-1',
                change: unstagedChange(),
                onOpenTab: onOpenTab,
              ),
            ),
          );
        },
        child: const Text('Show Diff'),
      ),
    );
  }
}
