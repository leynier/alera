import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/runs_fake_repository.dart';
import '../support/runs_harness.dart';

void main() => registerRunTerminalFocusTests();

void registerRunTerminalFocusTests() {
  for (final returnToWorkspace in [false, true]) {
    testWidgets(
      returnToWorkspace
          ? 'Return to Workspace restores retained terminal keyboard focus'
          : 'Open Terminal restores retained terminal keyboard focus',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final base = runsWorkbenchState();
        // Only the worker terminal, so it is the pane focus returns to.
        final seed = base.copyWith(
          activeProjectId: 'project-1',
          activeWorkspaceId: 'ws-1',
          tabsByWorkspace: {
            'ws-1': base
                .tabsFor('ws-1')
                .where((tab) => tab.id == 'w-3')
                .toList(),
          },
        );
        final repository = FakeRunRepository();
        final runtime = XtermTerminalRuntime();
        final container = runsContainer(
          repository,
          workbench: RunsTestWorkbench(seed: seed),
          terminalRuntime: runtime,
        );
        final workspace = seed.activeWorkspace!;
        final session = runtime.sessionFor(
          workspace: workspace,
          tab: seed.tabsFor(workspace.id).singleWhere((tab) => tab.id == 'w-3'),
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
                      final visible = ref
                          .watch(activityNavigationProvider)
                          .visible;
                      // Mirrors the shell: every exit from Activity restores
                      // the active pane once the retained panes are visible.
                      ref.listen(
                        activityNavigationProvider.select(
                          (value) => value.visible,
                        ),
                        (previous, next) {
                          if (previous != true || next) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted ||
                                ref.read(activityNavigationProvider).visible) {
                              return;
                            }
                            KeyboardCommandDispatcher(
                              ref: ref,
                              context: context,
                            ).focusActivePane();
                          });
                        },
                      );

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Visibility(
                            visible: !visible,
                            maintainState: true,
                            child: view,
                          ),
                          if (visible) const ActivityPage(),
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
          final navigation = container.read(
            activityNavigationProvider.notifier,
          );
          navigation
            ..open()
            ..selectRun('run-1')
            ..selectTask('task-2');
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TextField).first);
          await tester.pump();
          expect(focus.canRequestFocus, isFalse);
          expect(focus.hasFocus, isFalse);
          await tester.tap(
            find.text(
              returnToWorkspace ? 'Return to Workspace' : 'Open Terminal',
            ),
          );
          await tester.pumpAndSettle();
          expect(container.read(activityNavigationProvider).visible, isFalse);
          expect(
            container.read(activityNavigationProvider).runs.taskId,
            'task-2',
          );
          expect(runtime.peekSession(session.tabId), same(session));
          expect(focus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          expect(keys, contains(LogicalKeyboardKey.keyA));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          runtime.dispose();
          await repository.dispose();
        }
      },
    );
  }
}
