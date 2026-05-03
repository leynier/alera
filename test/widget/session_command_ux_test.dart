import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/review_preset_selection.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required SessionState state,
  ValueChanged<String>? onSendInput,
  Future<List<CodexSkillMetadata>> Function()? onListSkills,
  ValueChanged<ComposerDraftItem>? onAddDraftItem,
  Future<List<String>> Function()? onListReviewBranches,
  Future<void> Function(ReviewPresetSelection preset, {String? value})?
  onStartReviewFromPreset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionWorkspaceView(
          state: state,
          onSendInput: onSendInput ?? (_) {},
          onInterruptTurn: () {},
          isTurnRunning: false,
          isInterrupting: false,
          onModelChanged: (_) {},
          activeReasoningEffort: state.activeReasoningEffort,
          supportedReasoningEfforts: const <String>['low', 'medium', 'high'],
          onReasoningEffortChanged: (_) {},
          activeSpeedMode: state.activeSpeedMode,
          onSpeedModeChanged: (_) {},
          isMarkdownEnabled: true,
          onMarkdownModeChanged: (_) {},
          rawLogExpanded: false,
          onAddAttachment: () {},
          onRemoveAttachment: (_) {},
          onRemoveFromQueue: (_) {},
          onSteerQueuedMessage: (_) {},
          onStartEditingPendingMessage: (_) {},
          onUpdatePendingMessage: (_, _, _) {},
          onDeletePendingMessage: (_) {},
          onFinishEditingPendingMessage: () {},
          onPlanModeToggled: () {},
          onImplementPlanPressed: () async {},
          onPermissionModeToggled: () {},
          onApproveRequest: (_, {forSession = false}) async {},
          onDeclineRequest: (_) async {},
          onSubmitUserInput: (_) {},
          onDismissUserInput: () {},
          onListSkills: onListSkills,
          onAddDraftItem: onAddDraftItem,
          onListReviewBranches: onListReviewBranches,
          onStartReviewFromPreset: onStartReviewFromPreset,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  SessionState buildState() {
    return SessionState(
      selectedWorkspacePath: '/repo',
      availableCommands: builtinAleraCommands(),
    );
  }

  testWidgets('/status opens a modal instead of sending chat input', (
    tester,
  ) async {
    final sent = <String>[];
    await _pumpWorkspace(tester, state: buildState(), onSendInput: sent.add);

    await tester.enterText(find.byType(TextField).first, '/status');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.text('Current status'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
  });

  testWidgets('/status can be closed from the top-right button', (
    tester,
  ) async {
    await _pumpWorkspace(tester, state: buildState());

    await tester.enterText(find.byType(TextField).first, '/status');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current status'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('status-dialog-close-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current status'), findsNothing);
  });

  testWidgets('/review can execute the uncommitted preset directly', (
    tester,
  ) async {
    final calls = <(ReviewPresetSelection, String?)>[];
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onStartReviewFromPreset: (preset, {value}) async {
        calls.add((preset, value));
      },
    );

    await tester.enterText(find.byType(TextField).first, '/review');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a review preset'), findsOneWidget);
    await tester.tap(find.text('Review uncommitted changes'));
    await tester.pumpAndSettle();

    expect(calls, <(ReviewPresetSelection, String?)>[
      (ReviewPresetSelection.uncommittedChanges, null),
    ]);
  });

  testWidgets('/review branch preset opens a second filtered branch picker', (
    tester,
  ) async {
    final calls = <(ReviewPresetSelection, String?)>[];
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onListReviewBranches: () async => <String>[
        'main',
        'origin/main',
        'feature/demo',
      ],
      onStartReviewFromPreset: (preset, {value}) async {
        calls.add((preset, value));
      },
    );

    await tester.enterText(find.byType(TextField).first, '/review');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review against a base branch'));
    await tester.pumpAndSettle();

    expect(find.text('Select a base branch'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'origin/');
    await tester.pumpAndSettle();
    expect(find.text('origin/main'), findsOneWidget);
    expect(find.text('feature/demo'), findsNothing);

    await tester.tap(find.text('origin/main'));
    await tester.pumpAndSettle();

    expect(calls, <(ReviewPresetSelection, String?)>[
      (ReviewPresetSelection.baseBranch, 'origin/main'),
    ]);
  });

  testWidgets('/review preset picker uses a rounded filter input', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onStartReviewFromPreset: (_, {value}) async {},
    );

    await tester.enterText(find.byType(TextField).first, '/review');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    final presetFilter = tester.widget<TextField>(find.byType(TextField).last);
    final decoration = presetFilter.decoration!;
    final border = decoration.focusedBorder! as OutlineInputBorder;

    expect(border.borderRadius, BorderRadius.circular(AleraTokens.radiusPill));
  });

  testWidgets('/review branch picker uses a rounded filter input', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onListReviewBranches: () async => <String>[
        'main',
        'origin/main',
        'feature/demo',
      ],
      onStartReviewFromPreset: (_, {value}) async {},
    );

    await tester.enterText(find.byType(TextField).first, '/review');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review against a base branch'));
    await tester.pumpAndSettle();

    final branchFilter = tester.widget<TextField>(find.byType(TextField).last);
    final decoration = branchFilter.decoration!;
    final border = decoration.focusedBorder! as OutlineInputBorder;

    expect(border.borderRadius, BorderRadius.circular(AleraTokens.radiusPill));
  });

  testWidgets('skills picker supports filtering before selection', (
    tester,
  ) async {
    final added = <ComposerDraftItem>[];
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onListSkills: () async => const <CodexSkillMetadata>[
        CodexSkillMetadata(
          name: 'alpha-skill',
          description: 'Alpha description',
          path: '/tmp/alpha',
          scope: 'repo',
          enabled: true,
        ),
        CodexSkillMetadata(
          name: 'beta-skill',
          description: 'Beta description',
          path: '/tmp/beta',
          scope: 'repo',
          enabled: true,
        ),
      ],
      onAddDraftItem: added.add,
    );

    await tester.enterText(find.byType(TextField).first, '/skills');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a skill'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'beta');
    await tester.pumpAndSettle();

    expect(find.text('beta-skill'), findsOneWidget);
    expect(find.text('alpha-skill'), findsNothing);

    await tester.tap(find.text('beta-skill'));
    await tester.pumpAndSettle();

    expect(added.single.name, 'beta-skill');
  });

  testWidgets('skills picker uses a rounded filter input', (tester) async {
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onListSkills: () async => const <CodexSkillMetadata>[
        CodexSkillMetadata(
          name: 'alpha-skill',
          description: 'Alpha description',
          path: '/tmp/alpha',
          scope: 'repo',
          enabled: true,
        ),
      ],
      onAddDraftItem: (_) {},
    );

    await tester.enterText(find.byType(TextField).first, '/skills');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    final skillFilter = tester.widget<TextField>(find.byType(TextField).last);
    final decoration = skillFilter.decoration!;
    final border = decoration.focusedBorder! as OutlineInputBorder;

    expect(border.borderRadius, BorderRadius.circular(AleraTokens.radiusPill));
  });

  testWidgets('skills picker can be closed from the top-right button', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      state: buildState(),
      onListSkills: () async => const <CodexSkillMetadata>[
        CodexSkillMetadata(
          name: 'alpha-skill',
          description: 'Alpha description',
          path: '/tmp/alpha',
          scope: 'repo',
          enabled: true,
        ),
      ],
      onAddDraftItem: (_) {},
    );

    await tester.enterText(find.byType(TextField).first, '/skills');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a skill'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('filter-dialog-close-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a skill'), findsNothing);
  });
}
