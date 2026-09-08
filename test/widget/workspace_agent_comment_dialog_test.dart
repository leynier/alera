import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps Add Comment disabled until the body has text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WorkspaceAgentCommentDialog(
          title: 'Comment on File',
          path: 'lib/a.dart',
          locationLabel: 'lib/a.dart · line 4',
          snippet: 'void start() {}',
        ),
      ),
    );

    expect(find.text('Comment on File'), findsOneWidget);
    expect(find.text('lib/a.dart · line 4'), findsOneWidget);
    expect(find.text('void start() {}'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add Comment'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'Extract this helper.');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add Comment'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('returns the trimmed comment body', (tester) async {
    String? body;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                body = await showWorkspaceAgentCommentDialog(
                  context,
                  title: 'Comment on Diff',
                  path: 'lib/b.dart',
                  locationLabel: 'lib/b.dart (Unstaged)',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Fix this.  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Comment'));
    await tester.pumpAndSettle();

    expect(body, 'Fix this.');
  });
}
