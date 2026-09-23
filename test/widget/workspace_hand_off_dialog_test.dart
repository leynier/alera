import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/presentation/workspace_hand_off_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hand off from main asks for a new branch name', (tester) async {
    WorkspaceHandOffRequest? request;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                request = await showWorkspaceHandOffDialog(
                  context: context,
                  currentBranch: 'main',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'feat/isolated');
    await tester.ensureVisible(find.text('Confirm Shared Impact'));
    await tester.tap(find.text('Confirm Shared Impact'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Hand Off'));
    await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
    await tester.pumpAndSettle();

    expect(request?.branch, 'feat/isolated');
    expect(request?.reuseExistingBranch, isFalse);
    expect(request?.moveChanges, isFalse);
  });

  testWidgets(
    'hand off moves the current branch with an explicit replacement',
    (tester) async {
      WorkspaceHandOffRequest? request;
      await tester.pumpWidget(
        MaterialApp(
          theme: aleraDarkTheme,
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  request = await showWorkspaceHandOffDialog(
                    context: context,
                    currentBranch: 'feat/current',
                    defaultBranch: 'main',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'feat/current');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm Shared Impact'));
      await tester.tap(find.text('Confirm Shared Impact'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pumpAndSettle();
      expect(request, isNull);
      expect(
        find.text('Choose a different existing branch for the project folder'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(1), 'main');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm Shared Impact'));
      await tester.tap(find.text('Confirm Shared Impact'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pumpAndSettle();

      expect(request?.branch, 'feat/current');
      expect(request?.reuseExistingBranch, isTrue);
      expect(request?.replacementBranch, 'main');
      expect(request?.moveChanges, isTrue);
    },
  );
}
