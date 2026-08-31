import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_page.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_fixtures.dart';
import '../support/run_board_widget_harness.dart';

void main() => registerRunBoardTerminalFocusTests();

void registerRunBoardTerminalFocusTests() {
  testWidgets('Open Terminal restores retained terminal keyboard focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seed = boardWorkbenchState().copyWith(
      activeProjectId: 'project-1',
      activeWorkspaceId: 'ws-1',
    );
    final repository = BoardTestRepository();
    final runtime = XtermTerminalRuntime();
    final container = boardContainer(
      repository,
      workbench: BoardTestWorkbench(seed: seed),
      terminalRuntime: runtime,
    );
    final executionWorkspace = seed
        .workspacesFor('project-1')
        .singleWhere((workspace) => workspace.id == 'workflow-attempt-2');
    final session = runtime.sessionFor(
      workspace: executionWorkspace,
      tab: seed.tabsFor(executionWorkspace.id).single,
    );
    final focus = terminalFocusNodeForTesting(session);
    final keys = <LogicalKeyboardKey>[];
    final view = session.buildView(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) keys.add(event.logicalKey);
        return KeyEventResult.handled;
      },
    );
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAleraDarkTheme(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final visible = ref.watch(runBoardNavigationProvider).visible;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Visibility(
                        visible: !visible,
                        maintainState: true,
                        child: view,
                      ),
                      if (visible) const RunBoardPage(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final navigation = container.read(runBoardNavigationProvider.notifier);
      navigation
        ..open()
        ..selectRun('run-1')
        ..selectTask('task-2');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(focus.canRequestFocus, isFalse);
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.text('Open Terminal'));
      await tester.pumpAndSettle();
      expect(container.read(runBoardNavigationProvider).visible, isFalse);
      expect(container.read(runBoardNavigationProvider).taskId, 'task-2');
      expect(runtime.peekSession(session.tabId), same(session));
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(keys, contains(LogicalKeyboardKey.keyA));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      runtime.dispose();
      repository.dispose();
    }
  });
}
