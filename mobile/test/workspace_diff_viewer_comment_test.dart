import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
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
}
