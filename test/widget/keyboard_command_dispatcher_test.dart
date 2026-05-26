import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    dispatcher.dispatch(KeyboardActionId.newTerminalTab);
    await tester.pump();

    dispatcher.dispatch(KeyboardActionId.nextTab);
    dispatcher.dispatch(KeyboardActionId.previousTab);
    dispatcher.dispatch(KeyboardActionId.goToTab2);
    dispatcher.dispatch(KeyboardActionId.goToTab9);
    await tester.pump();

    dispatcher.dispatch(KeyboardActionId.closeTab);
    await tester.pump();

    expect(controller.createdTerminalWorkspaceIds, <String>[workspace.id]);
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
    expect(find.text('General'), findsWidgets);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();

    dispatcher.dispatch(KeyboardActionId.addProject);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Project path'), findsOneWidget);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();

    dispatcher.dispatch(KeyboardActionId.createWorkspace);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'Create workspace'),
      findsOneWidget,
    );
  });
}

Project _project() {
  return Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/tmp/alera',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Workspace _workspace() {
  return Workspace(
    id: 'ws-1',
    projectId: 'project-1',
    name: 'Main',
    branch: 'main',
    path: '/tmp/alera',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({required String id}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'ws-1',
    title: 'Terminal',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _DispatcherTestWorkbenchController extends WorkbenchController {
  _DispatcherTestWorkbenchController(this._seed, {this.createdTab})
    : _splitCompleter = Completer<WorkspaceTabRecord>();

  final WorkbenchState _seed;
  final WorkspaceTabRecord? createdTab;
  final List<String> sourceBranches = <String>['main'];

  final Completer<WorkspaceTabRecord> _splitCompleter;
  final List<String> createdTerminalWorkspaceIds = <String>[];
  final List<String> closedTabIds = <String>[];
  final List<String> selectedTabIds = <String>[];
  final List<({String workspaceId, String groupId, WorkbenchDropZone zone})>
  splitRequests =
      <({String workspaceId, String groupId, WorkbenchDropZone zone})>[];
  final List<({String workspaceId, String groupId})> mergedSplits =
      <({String workspaceId, String groupId})>[];

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  void setCollapsed(bool collapsed) {
    state = state.copyWith(collapsed: collapsed);
  }

  @override
  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) {
    splitRequests.add((
      workspaceId: workspace.id,
      groupId: groupId,
      zone: zone,
    ));
    return _splitCompleter.future;
  }

  @override
  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    createdTerminalWorkspaceIds.add(workspace.id);
    final tab = createdTab ?? _tab(id: 'tab-new');
    final currentTabs = state.tabsFor(workspace.id);
    final layout = state.layoutFor(workspace.id);
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        workspace.id: <WorkspaceTabRecord>[...currentTabs, tab],
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null)
          workspace.id: layout.addTabToGroup(
            groupId: targetGroupId ?? layout.activeGroupId,
            tabId: tab.id,
          ),
      },
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspace.id: tab.id,
      },
    );
    return tab;
  }

  @override
  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    closedTabIds.add(tabId);
  }

  @override
  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    selectedTabIds.add(tabId);
    final layout = state.layoutFor(workspaceId);
    if (layout == null) {
      return;
    }
    state = state.copyWith(
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
    );
  }

  @override
  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    mergedSplits.add((workspaceId: workspaceId, groupId: groupId));
  }

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    return sourceBranches;
  }

  void completeSplit(WorkspaceTabRecord tab) {
    if (_splitCompleter.isCompleted) {
      return;
    }
    _splitCompleter.complete(tab);
  }
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedTabIds = <String>[];
  final Set<String> everFocusedTabIds = <String>{};

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(
        workspace: workspace,
        tab: tab,
        onFocus: () => everFocusedTabIds.add(tab.id),
      ),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({
    required this.workspace,
    required this.tab,
    required this.onFocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final VoidCallback onFocus;
  int requestFocusCalls = 0;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart() async {}

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return const SizedBox.shrink();
  }

  @override
  void requestFocus() {
    requestFocusCalls += 1;
    onFocus();
  }
}

class _DispatcherPumpHarness {
  const _DispatcherPumpHarness({required this.ref, required this.context});

  final WidgetRef ref;
  final BuildContext context;
}

Future<_DispatcherPumpHarness> _pumpDispatcherHarness(
  WidgetTester tester, {
  required _DispatcherTestWorkbenchController controller,
  required _FakeTerminalRuntime runtime,
}) async {
  final container = ProviderContainer(
    overrides: [
      workbenchControllerProvider.overrideWith(() => controller),
      terminalRuntimeProvider.overrideWith((ref) => runtime),
      settingsControllerProvider.overrideWith(
        () => _DispatcherSettingsController(AleraSettings.defaults),
      ),
    ],
  );
  addTearDown(container.dispose);

  late WidgetRef dispatcherRef;
  late BuildContext dispatcherContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            dispatcherRef = ref;
            dispatcherContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return _DispatcherPumpHarness(ref: dispatcherRef, context: dispatcherContext);
}

class _DispatcherSettingsController extends SettingsController {
  _DispatcherSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}
