import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/presentation/workspace_hand_off_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(
  WidgetTester tester,
  Future<void> Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: aleraDarkTheme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => action(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('custom default automatically suggests an editable branch', (
    tester,
  ) async {
    WorkspaceHandOffRequest? result;
    await open(tester, (context) async {
      result = await showWorkspaceHandOffDialog(
        context: context,
        currentBranch: 'trunk',
        defaultBranch: 'trunk',
        generateBranch: () async => 'fix/generated',
      );
    });
    expect(find.text('fix/generated'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'fix/manual');
    await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
    await tester.pumpAndSettle();
    expect(result?.branch, 'fix/manual');
    expect(result?.reuseExistingBranch, isFalse);
  });

  testWidgets('branch named main is reused when actual default is trunk', (
    tester,
  ) async {
    WorkspaceHandOffRequest? result;
    var generations = 0;
    await open(tester, (context) async {
      result = await showWorkspaceHandOffDialog(
        context: context,
        currentBranch: 'main',
        defaultBranch: 'trunk',
        generateBranch: () async {
          generations++;
          return 'fix/new';
        },
      );
    });
    expect(generations, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
    await tester.pumpAndSettle();
    expect(result?.branch, 'main');
    expect(result?.reuseExistingBranch, isTrue);
  });

  testWidgets(
    'manual edit wins over a late suggestion and cancellation stops generation',
    (tester) async {
      final generated = Completer<String>();
      var cancelled = 0;
      await open(tester, (context) async {
        await showWorkspaceHandOffDialog(
          context: context,
          currentBranch: 'trunk',
          defaultBranch: 'trunk',
          generateBranch: () => generated.future,
          cancelGeneration: () async {
            cancelled++;
          },
        );
      });
      await tester.enterText(find.byType(TextField).first, 'fix/manual');
      generated.complete('fix/stale');
      await tester.pumpAndSettle();
      expect(find.text('fix/manual'), findsOneWidget);
      expect(find.text('fix/stale'), findsNothing);
      final beforeClose = cancelled;
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cancelled, greaterThan(beforeClose));
    },
  );

  testWidgets(
    'AI errors allow manual fallback and collision validation stays open',
    (tester) async {
      WorkspaceHandOffRequest? result;
      await open(tester, (context) async {
        result = await showWorkspaceHandOffDialog(
          context: context,
          currentBranch: 'main',
          defaultBranch: 'main',
          generateBranch: () async => throw StateError('provider unavailable'),
          validateBranch: (branch) async =>
              branch == 'fix/taken' ? 'Branch already exists' : null,
        );
      });
      expect(find.textContaining('AI Assist failed'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'fix/taken');
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pumpAndSettle();
      expect(find.text('Branch already exists'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(find.byType(TextField).first, 'fix/available');
      await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
      await tester.pumpAndSettle();
      expect(result?.branch, 'fix/available');
    },
  );

  testWidgets('late validation cannot submit a manually changed branch', (
    tester,
  ) async {
    final validation = Completer<String?>();
    WorkspaceHandOffRequest? result;
    await open(tester, (context) async {
      result = await showWorkspaceHandOffDialog(
        context: context,
        currentBranch: 'feature',
        defaultBranch: 'main',
        validateBranch: (_) => validation.future,
      );
    });
    await tester.tap(find.widgetWithText(FilledButton, 'Hand Off'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'fix/changed');
    validation.complete(null);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('fix/changed'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
