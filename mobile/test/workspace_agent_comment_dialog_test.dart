import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps Add Comment disabled until the body has text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const WorkspaceAgentCommentDialog(
          title: 'Comment on Diff',
          path: 'lib/a.dart',
          locationLabel: 'lib/a.dart · line 4',
          snippet: 'void start() {}',
        ),
      ),
    );

    expect(find.text('Comment on Diff'), findsOneWidget);
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
}
