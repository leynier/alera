import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_detail.dart';
import 'package:alera/src/features/orchestration/presentation/run_task_inspector.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_fixtures.dart';
import '../support/run_board_widget_harness.dart';

void main() {
  Future<({ProviderContainer container, BoardTestRepository repository})> mount(
    WidgetTester tester, {
    Size size = const Size(1100, 800),
    double scale = 1,
    Object? error,
    BoardTestWorkbench? workbench,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = BoardTestRepository()..error = error;
    final container = boardContainer(repository, workbench: workbench);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    container.read(runBoardNavigationProvider.notifier).open();
    await tester.pumpWidget(BoardTestApp(container: container, scale: scale));
    await tester.pumpAndSettle();
    return (container: container, repository: repository);
  }

  testWidgets(
    'run and task selection never changes workspace; closing releases reads',
    (tester) async {
      final f = await mount(tester);
      await tester.tap(find.text('Deliver reviewed workflow plans'));
      await tester.pumpAndSettle();
      expect(find.byType(RunBoardDetail), findsOneWidget);
      expect(
        f.container.read(workbenchControllerProvider).activeWorkspaceId,
        'ws-2',
      );
      await tester.ensureVisible(find.text('Build the review surface'));
      await tester.tap(find.text('Build the review surface'));
      await tester.pumpAndSettle();
      expect(find.byType(RunTaskInspector), findsOneWidget);
      expect(
        f.container.read(workbenchControllerProvider).activeWorkspaceId,
        'ws-2',
      );
      expect(f.repository.watchers, 2);
      await tester.tap(find.text('Return to Workspace'));
      await tester.pumpAndSettle();
      expect(f.repository.watchers, 0);
      expect(f.container.read(runBoardNavigationProvider).taskId, 'task-2');
      await tester.tap(find.text('Open Run Board'));
      await tester.pumpAndSettle();
      expect(find.byType(RunTaskInspector), findsOneWidget);
    },
  );

  testWidgets('many runs build lazily and do not request per-run details', (
    tester,
  ) async {
    final f = await mount(tester);
    f.repository.board = boardSnapshot(
      items: [
        for (var index = 0; index < 1000; index++)
          boardRun(
            id: 'run-$index',
            objective: 'A very long objective $index ' * 12,
          ),
      ],
    );
    f.repository.events.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(AleraActivityRow).evaluate().length, lessThan(20));
    expect(f.repository.runReads, 0);
    expect(f.repository.taskReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime reordering does not steal focus from a run row', (
    tester,
  ) async {
    final f = await mount(tester);
    for (var step = 0; step < 30; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<AleraActivityRow>() !=
          null) {
        break;
      }
    }
    final focus = FocusManager.instance.primaryFocus;
    final row = focus?.context
        ?.findAncestorWidgetOfExactType<AleraActivityRow>();
    expect(row, isNotNull);
    f.repository.board = boardSnapshot(
      revision: 2,
      items: [
        boardRun(id: 'newer'),
        ...f.repository.board.items,
      ],
    );
    f.repository.events.add(null);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, focus);
    expect(
      focus?.context?.findAncestorWidgetOfExactType<AleraActivityRow>()?.key,
      row!.key,
    );
  });

  testWidgets('empty runs and unavailable workspaces explain their state', (
    tester,
  ) async {
    final f = await mount(
      tester,
      workbench: BoardTestWorkbench(
        seed: boardWorkbenchState().copyWith(
          projects: [],
          workspacesByProject: {},
        ),
      ),
    );
    f.container.read(runBoardNavigationProvider.notifier).selectRun('run-1');
    await tester.pumpAndSettle();
    expect(
      find.text('The owning workspace is unavailable on this host.'),
      findsOneWidget,
    );
    final open = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Open Workspace'),
    );
    expect(open.onPressed, isNull);
    f.container.read(runBoardNavigationProvider.notifier).selectRun(null);
    f.repository.board = RunBoardSnapshot(
      revision: 2,
      counts: const RunBoardCounts(attention: 0, active: 0, history: 0),
      items: [],
    );
    f.repository.events.add(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('No runs match this view.'), findsOneWidget);
  });

  testWidgets('explicit terminal and diff actions preserve board selection', (
    tester,
  ) async {
    final workbench = BoardTestWorkbench();
    final f = await mount(tester, workbench: workbench);
    final navigation = f.container.read(runBoardNavigationProvider.notifier);
    navigation.selectRun('run-1');
    navigation.selectTask('task-2');
    await tester.pumpAndSettle();
    expect(find.text('Result Ready'), findsWidgets);
    expect(
      find.text(
        'The worker result passed its contract and is waiting for local integration.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Terminal'));
    await tester.pumpAndSettle();
    expect(workbench.actions, [
      'workspace:workflow-attempt-2',
      'terminal:session-1',
    ]);
    expect(f.container.read(runBoardNavigationProvider).visible, isFalse);
    navigation.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Diff'));
    await tester.pumpAndSettle();
    expect(workbench.actions.last, 'diff:workflow-attempt-2');
    expect(f.container.read(runBoardNavigationProvider).taskId, 'task-2');
  });

  testWidgets('runtime events retain search focus and typing is debounced', (
    tester,
  ) async {
    final f = await mount(tester);
    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.enterText(field, 'contract');
    await tester.pump(const Duration(milliseconds: 100));
    expect(f.repository.boardReads, 1);
    final focus = FocusManager.instance.primaryFocus;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(f.repository.queries.last.search, 'contract');
    expect(FocusManager.instance.primaryFocus, focus);
    f.repository.events.add(null);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, focus);
    await tester.enterText(field, '日' * 100);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Search is limited to 256 UTF-8 bytes.'), findsOneWidget);
    expect(f.repository.queries.last.search, 'contract');
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(f.repository.queries.last.search, isNull);
  });

  testWidgets(
    'incompatible and disconnected hosts keep recovery and filters usable',
    (tester) async {
      final f = await mount(tester, error: const RunBoardUpdateRequired());
      expect(find.text('Update Required'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
      f.repository.error = StateError('connection closed');
      f.repository.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Run Board Unavailable'), findsOneWidget);
      f.repository.error = null;
      await tester.tap(find.byTooltip('Refresh Run Board'));
      await tester.pumpAndSettle();
      expect(find.text('Deliver reviewed workflow plans'), findsOneWidget);
    },
  );

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'compact layout supports text scale $scale and back navigation',
      (tester) async {
        final f = await mount(tester, size: const Size(420, 640), scale: scale);
        expect(tester.takeException(), isNull);
        f.container
            .read(runBoardNavigationProvider.notifier)
            .selectRun('run-1');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(RunBoardDetail), findsOneWidget);
        await tester.tap(find.text('All Runs'));
        await tester.pumpAndSettle();
        expect(find.text('Clear Filters'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'central keyboard command opens board and rows activate with Enter',
    (tester) async {
      final f = await mount(tester);
      f.container.read(runBoardNavigationProvider.notifier).close();
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(Consumer).first);
      KeyboardCommandDispatcher(
        ref: element as WidgetRef,
        context: element,
      ).dispatch(KeyboardActionId.openRunBoard);
      await tester.pumpAndSettle();
      var reachedRow = false;
      for (var step = 0; step < 30; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reachedRow =
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<AleraActivityRow>() !=
            null;
        if (reachedRow) break;
      }
      expect(reachedRow, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(RunBoardDetail), findsOneWidget);
    },
  );
}
