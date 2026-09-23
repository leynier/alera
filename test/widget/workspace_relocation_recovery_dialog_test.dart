import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_relocation_recovery.dart';
import 'package:alera/src/features/workbench/presentation/workspace_relocation_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceRelocationRecoverySnapshot history({
  bool completed = false,
  String? attemptId = 'original-attempt',
  bool hasSetupRecipe = false,
}) => WorkspaceRelocationRecoverySnapshot(
  ownerError: 'SSH disconnected',
  entries: [
    WorkspaceRelocationRecoveryEntry(
      id: 'saved-operation',
      source: Workspace(
        id: 'task',
        instanceId: 'instance',
        projectId: 'project',
        name: 'Task',
        path: '/owner/project',
        hostId: 'ssh',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        kind: .main,
        status: .active,
      ),
      phase: 'awaitingOwner',
      completed: completed,
      toProjectCheckout: false,
      moveChanges: false,
      branch: 'saved-branch',
      setupAttemptId: attemptId,
      hasSetupRecipe: hasSetupRecipe,
      processObservations: ['unknown: Process closure cannot be verified'],
    ),
  ],
);

Future<void> open(
  WidgetTester tester,
  Future<WorkspaceRelocationRecoverySnapshot> Function() load, {
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onResume,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onRunSetup,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onCancelSetup,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: aleraDarkTheme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showWorkspaceRelocationRecoveryDialog(
            context: context,
            load: load,
            onResume: onResume,
            onRunSetup: onRunSetup,
            onCancelSetup: onCancelSetup,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
}

void main() {
  testWidgets(
    'setup cancellation remains available while execution is pending',
    (tester) async {
      var started = false;
      var canceled = false;
      final execution = Completer<void>();
      await open(
        tester,
        () async => history(
          completed: true,
          hasSetupRecipe: true,
          attemptId: started ? 'running-attempt' : null,
        ),
        onRunSetup: (entry) async {
          started = true;
          await execution.future;
        },
        onCancelSetup: (entry) async {
          expect(entry.setupAttemptId, 'running-attempt');
          canceled = true;
        },
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Run Setup'));
      await tester.tap(find.text('Run Setup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Run Setup'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(started, isTrue);
      await tester.tap(find.text('Refresh'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Cancel Setup'));
      await tester.tap(find.text('Cancel Setup'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel Setup'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(canceled, isTrue);
      expect(execution.isCompleted, isFalse);
      execution.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resume requires explicit shared-impact confirmation and retains the saved operation',
    (tester) async {
      final resumed = <String>[];
      await open(
        tester,
        () async => history(),
        onResume: (entry) async {
          resumed.add(entry.id);
        },
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Resume'));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Resume Hand Off?'), findsOneWidget);
      expect(find.textContaining('shared by other tasks'), findsOneWidget);
      expect(resumed, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();
      expect(resumed, ['saved-operation']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline owner preserves original choices and unknown process state',
    (tester) async {
      var requests = 0;
      await open(tester, () async {
        requests++;
        return history();
      });
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Transfer ID: saved-operation'), findsOneWidget);
      expect(find.text('Branch: saved-branch'), findsOneWidget);
      expect(
        find.textContaining('Remote process closure has not been verified'),
        findsOneWidget,
      );
      expect(
        find.text('unknown: Process closure cannot be verified'),
        findsOneWidget,
      );
      expect(find.text('Hand Off: pending'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh failure retains previously loaded evidence', (
    tester,
  ) async {
    var requests = 0;
    await open(tester, () async {
      if (++requests == 1) return history();
      throw StateError('Disconnected');
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(
      find.textContaining('Previously loaded history is shown below'),
      findsOneWidget,
    );
    expect(find.text('Transfer ID: saved-operation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during inspection does not update disposed state', (
    tester,
  ) async {
    final pending = Completer<WorkspaceRelocationRecoverySnapshot>();
    await open(tester, () => pending.future);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Close'));
    pending.complete(history());
    await tester.pumpAndSettle();
    expect(find.text('Workspace Recovery'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
