import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
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
  _DispatcherTestWorkbenchController(this._seed)
    : _splitCompleter = Completer<WorkspaceTabRecord>();

  final WorkbenchState _seed;

  final Completer<WorkspaceTabRecord> _splitCompleter;

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) {
    return _splitCompleter.future;
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
      () => _FakeTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
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
  _FakeTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
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
  }
}
