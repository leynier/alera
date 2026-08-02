import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/browser/application/browser_providers.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_command_palette_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'keyboard_command_dispatcher_test_harness.dart';

class _DispatcherAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

void main() {
  testWidgets('split command stays safe after the dispatcher host unmounts', (
    tester,
  ) async {
    final workspace = _workspace();
    final initialTab = _tab(id: 'tab-1');
    final splitTab = _tab(id: 'tab-2');
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[initialTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[initialTab.id],
          ),
        },
        activeWorkspaceId: workspace.id,
      ),
    );
    final runtime = _FakeTerminalRuntime();
    final container = ProviderContainer(
      overrides: [
        workbenchControllerProvider.overrideWith(() => controller),
        terminalRuntimeProvider.overrideWith((ref) => runtime),
      ],
    );
    addTearDown(container.dispose);

    final showHost = ValueNotifier<bool>(true);
    addTearDown(showHost.dispose);

    late WidgetRef dispatcherRef;
    late BuildContext dispatcherContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showHost,
            builder: (context, visible, _) {
              if (!visible) {
                return const SizedBox.shrink();
              }
              return Consumer(
                builder: (context, ref, _) {
                  dispatcherRef = ref;
                  dispatcherContext = context;
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ),
    );

    KeyboardCommandDispatcher(
      ref: dispatcherRef,
      context: dispatcherContext,
    ).dispatch(KeyboardActionId.splitRight);

    showHost.value = false;
    await tester.pump();

    controller.completeSplit(splitTab);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(runtime.focusedTabIds, contains(splitTab.id));
  });

  testWidgets('tab commands create, navigate, and close tabs', (tester) async {
    final workspace = _workspace();
    final firstTab = _tab(id: 'tab-1');
    final secondTab = _tab(id: 'tab-2');
    final thirdTab = _tab(id: 'tab-3');
    final newTab = _tab(id: 'tab-4');
    final groupId = WorkbenchLayout.defaultGroupId(workspace.id);
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[firstTab, secondTab, thirdTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[firstTab.id, secondTab.id, thirdTab.id],
          ).setActiveTab(groupId: groupId, tabId: firstTab.id),
        },
        activeWorkspaceId: workspace.id,
        activeTabIdByWorkspace: <String, String>{workspace.id: firstTab.id},
      ),
      createdTab: newTab,
    );
    final runtime = _FakeTerminalRuntime();
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: runtime,
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );
    final activeSession = runtime.sessionFor(
      workspace: workspace,
      tab: firstTab,
    );

    dispatcher.dispatch(KeyboardActionId.toggleTerminalComposer);
    expect(activeSession.composerController.visible, isTrue);

    dispatcher.dispatch(KeyboardActionId.newTerminalTab);
    await tester.pump();
    dispatcher.dispatch(KeyboardActionId.newBrowserTab);
    await tester.pump();

    dispatcher.dispatch(KeyboardActionId.nextTab);
    dispatcher.dispatch(KeyboardActionId.previousTab);
    dispatcher.dispatch(KeyboardActionId.goToTab2);
    dispatcher.dispatch(KeyboardActionId.goToTab9);
    await tester.pump();

    dispatcher.dispatch(KeyboardActionId.closeTab);
    await tester.pump();

    expect(controller.createdTerminalWorkspaceIds, <String>[workspace.id]);
    expect(controller.createdBrowserWorkspaceIds, <String>[workspace.id]);
    expect(runtime.everFocusedTabIds, contains(newTab.id));
    expect(controller.selectedTabIds, <String>[
      firstTab.id,
      newTab.id,
      secondTab.id,
      newTab.id,
    ]);
    expect(runtime.closedTabIds, <String>[newTab.id]);
    expect(controller.closedTabIds, <String>[newTab.id]);
  });

  testWidgets('worktree navigation commands use the controller history', (
    tester,
  ) async {
    final controller = _DispatcherTestWorkbenchController(
      const WorkbenchState(),
    );
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: _FakeTerminalRuntime(),
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );

    dispatcher.dispatch(KeyboardActionId.navigateBack);
    dispatcher.dispatch(KeyboardActionId.navigateForward);
    await tester.pump();

    expect(controller.navigationCalls, <String>['back', 'forward']);
  });

  testWidgets('closeSplit merges only multi-pane layouts', (tester) async {
    final workspace = _workspace();
    final firstTab = _tab(id: 'tab-1');
    final secondTab = _tab(id: 'tab-2');
    final singleController = _DispatcherTestWorkbenchController(
      WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[firstTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[firstTab.id],
          ),
        },
        activeWorkspaceId: workspace.id,
      ),
    );
    final singleHarness = await _pumpDispatcherHarness(
      tester,
      controller: singleController,
      runtime: _FakeTerminalRuntime(),
    );

    KeyboardCommandDispatcher(
      ref: singleHarness.ref,
      context: singleHarness.context,
    ).dispatch(KeyboardActionId.closeSplit);
    await tester.pump();

    expect(singleController.mergedSplits, isEmpty);

    final splitLayout =
        WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[firstTab.id],
        ).splitWithGroup(
          targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
          zone: WorkbenchDropZone.right,
          newGroup: WorkbenchPaneGroup(
            id: 'group-2',
            tabIds: <String>[secondTab.id],
            activeTabId: secondTab.id,
          ),
        );
    final splitController = _DispatcherTestWorkbenchController(
      WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: splitLayout},
        activeWorkspaceId: workspace.id,
      ),
    );
    final splitHarness = await _pumpDispatcherHarness(
      tester,
      controller: splitController,
      runtime: _FakeTerminalRuntime(),
    );

    KeyboardCommandDispatcher(
      ref: splitHarness.ref,
      context: splitHarness.context,
    ).dispatch(KeyboardActionId.closeSplit);
    await tester.pump();

    expect(
      splitController.mergedSplits,
      <({String workspaceId, String groupId})>[
        (workspaceId: workspace.id, groupId: splitLayout.activeGroupId),
      ],
    );
  });

  testWidgets('splitDown dispatches the matching workbench zone', (
    tester,
  ) async {
    final workspace = _workspace();
    final firstTab = _tab(id: 'tab-1');
    final splitTab = _tab(id: 'tab-2');
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        workspacesByProject: <String, List<Workspace>>{
          workspace.projectId: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[firstTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[firstTab.id],
          ),
        },
        activeWorkspaceId: workspace.id,
      ),
    );
    final runtime = _FakeTerminalRuntime();
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: runtime,
    );

    KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    ).dispatch(KeyboardActionId.splitDown);
    await tester.pump();

    controller.completeSplit(splitTab);
    await tester.pump();

    expect(
      controller.splitRequests,
      <({String workspaceId, String groupId, WorkbenchDropZone zone})>[
        (
          workspaceId: workspace.id,
          groupId: WorkbenchLayout.defaultGroupId(workspace.id),
          zone: WorkbenchDropZone.down,
        ),
      ],
    );
  });

  testWidgets('dialog-oriented commands reuse the shared launchers', (
    tester,
  ) async {
    final project = _project();
    final workspace = _workspace();
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
      ),
    );
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: _FakeTerminalRuntime(),
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );

    dispatcher.dispatch(KeyboardActionId.toggleSidebar);
    expect(controller.state.collapsed, isTrue);

    dispatcher.dispatch(KeyboardActionId.openSettings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Application'), findsWidgets);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();

    dispatcher.dispatch(KeyboardActionId.openCommandPalette);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardCommandPaletteDialog), findsOneWidget);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();

    dispatcher.dispatch(KeyboardActionId.addProject);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Project Path'), findsOneWidget);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();

    dispatcher.dispatch(KeyboardActionId.createWorkspace);
    await tester.pumpAndSettle();
    expect(find.text('From Prompt'), findsOneWidget);
  });
}
