import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/domain/workflow_review_snapshot.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkflowReviewSnapshot _review() => WorkflowReviewSnapshot.fromJson({
  'challenge': {
    'version': 1,
    'runId': 'run',
    'revision': 2,
    'scope': 'plan',
    'planDigest': 'digest',
    'integrationSha': 'a' * 40,
    'expiresAt': 2000000000,
  },
  'plan': {
    'digest': 'digest',
    'objective': 'Add reviewed workflow execution',
    'recipe': {
      'source': {'origin': 'builtIn', 'id': 'quick-fix'},
      'recipe': {
        'name': 'Quick Fix',
        'stages': [
          {
            'id': 'fix',
            'name': 'Fix',
            'purpose': 'Make the scoped correction.',
            'dependsOn': [],
          },
        ],
      },
    },
    'profiles': {
      'profile': {'name': 'Selected Agent'},
    },
    'tasks': [
      {
        'profileId': 'profile',
        'task': {
          'id': 'task',
          'title': 'Update the workflow',
          'spec': 'Preserve existing behavior.',
          'roleId': 'implementer',
          'stageId': 'fix',
          'dependsOn': [],
        },
        'contract': {
          'contract': {
            'name': 'Implementation',
            'revision': 1,
            'purpose': 'Implement the change.',
            'instructions': 'Run focused tests.',
            'requiredArtifacts': ['test-report'],
            'checklist': [
              {'description': 'Tests pass.'},
            ],
          },
        },
      },
    ],
  },
  'tasks': [],
});

void main() {
  testWidgets('decisions require explicit action and notes for changes', (
    tester,
  ) async {
    final decisions = <(WorkflowHumanDecision, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: WorkflowReviewPanel(
            review: _review(),
            onDecision: (decision, reason) => decisions.add((decision, reason)),
            onBack: () {},
            onRefresh: () {},
            onInspectTask: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(decisions, isEmpty);
    expect(find.text('Quick Fix (Built-in)'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Request Changes'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Add regression coverage.');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Request Changes'));
    await tester.tap(find.text('Request Changes'));
    expect(decisions, [
      (WorkflowHumanDecision.requestChanges, 'Add regression coverage.'),
    ]);
    await tester.ensureVisible(find.text('Update the workflow'));
    await tester.tap(find.text('Update the workflow'));
    await tester.pumpAndSettle();
    expect(find.text('Required artifact: test-report'), findsOneWidget);
    expect(find.text('Check: Tests pass.'), findsOneWidget);
  });

  testWidgets(
    'invalidated review keeps notes and disables all decisions at compact scale',
    (tester) async {
      tester.view.physicalSize = const Size(420, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var invalidated = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: aleraDarkTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: Scaffold(
                  body: WorkflowReviewPanel(
                    review: _review(),
                    invalidated: invalidated,
                    onDecision: (_, _) =>
                        fail('Stale review must not be approved'),
                    onBack: () {},
                    onRefresh: () {},
                    onInspectTask: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'Keep these notes.');
      update(() => invalidated = true);
      await tester.pumpAndSettle();
      expect(find.text('Keep these notes.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Approve Plan'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve Plan'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Request Changes'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
