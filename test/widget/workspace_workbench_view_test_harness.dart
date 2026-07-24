part of 'workspace_workbench_view_test.dart';

const String _workspaceId = 'workspace-1';

Future<void> _pumpWorkbenchView(
  WidgetTester tester, {
  required List<WorkspaceTabRecord> tabs,
  required WorkbenchLayout? layout,
  required _FakeTerminalRuntime terminalRuntime,
  required List<String?> createdTabs,
  required List<_SelectedTabAction> selectedTabs,
  required List<String> closedTabs,
  required List<List<String>> closedTabGroups,
  required List<String> renamedTabs,
  required List<_MovedTabAction> movedTabs,
  required List<_SplitGroupAction> splitGroups,
  required List<String> mergedGroups,
  required List<_UpdatedSplitRatioAction> updatedRatios,
  List<String>? activatedGroups,
  Size size = const Size(420, 280),
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: WorkspaceWorkbenchView(
              project: _project(),
              workspace: _workspace(),
              tabs: tabs,
              layout: layout,
              terminalRuntime: terminalRuntime,
              agentStatuses: agentStatuses,
              completionAcknowledgements:
                  WorkbenchTabCompletionAcknowledgements(),
              onCreateTab: ({String? targetGroupId}) async {
                createdTabs.add(targetGroupId);
              },
              onOpenEditorTab: ({required relativePath, targetGroupId}) async {
                selectedTabs.add(
                  _SelectedTabAction(targetGroupId ?? 'group-a', relativePath),
                );
              },
              onOpenMarkdownViewerTab:
                  ({required relativePath, targetGroupId}) async {
                    selectedTabs.add(
                      _SelectedTabAction(
                        targetGroupId ?? 'group-a',
                        relativePath,
                      ),
                    );
                  },
              onSelectTab: ({required String groupId, required String tabId}) {
                selectedTabs.add(_SelectedTabAction(groupId, tabId));
              },
              onCloseTab: closedTabs.add,
              onCloseTabs: (tabIds) => closedTabGroups.add(tabIds),
              onRenameTab:
                  ({required String tabId, required String title}) async {
                    renamedTabs.add(title);
                  },
              onOpenEditor: (_) async {},
              onOpenMermanPreview: (_) async {},
              onMoveTab:
                  ({
                    required String tabId,
                    required String targetGroupId,
                    required WorkbenchDropZone zone,
                    int? index,
                  }) async {
                    movedTabs.add(
                      _MovedTabAction(tabId, targetGroupId, zone, index: index),
                    );
                  },
              onSplitGroup:
                  ({
                    required String groupId,
                    required WorkbenchDropZone zone,
                  }) async {
                    splitGroups.add(_SplitGroupAction(groupId, zone));
                  },
              onMergeGroup: ({required String groupId}) async {
                mergedGroups.add(groupId);
              },
              onActivateGroup: ({required String groupId}) {
                activatedGroups?.add(groupId);
              },
              onUpdateSplitRatio:
                  ({required List<int> nodePath, required double ratio}) {
                    updatedRatios.add(
                      _UpdatedSplitRatioAction(nodePath, ratio),
                    );
                  },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openTabContextMenu(WidgetTester tester, String title) async {
  await tester.tapAt(
    tester.getCenter(find.text(title).first),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Project _project() => Project(
  id: 'project-1',
  name: 'Alera',
  repoPath: '/tmp/alera',
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
);

Workspace _workspace() => Workspace(
  id: _workspaceId,
  projectId: 'project-1',
  name: 'Main',
  branch: 'main',
  path: '/tmp/alera',
  createdAt: DateTime.utc(2026, 5, 22),
  updatedAt: DateTime.utc(2026, 5, 22),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

WorkspaceTabRecord _tab(
  String id, {
  required String title,
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
  String? filePath,
  bool mermanPreview = false,
}) {
  final payload = filePath == null
      ? const <String, Object?>{}
      : <String, Object?>{
          workspaceTabFilePathPayloadKey: filePath,
          if (mermanPreview)
            workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
        };
  return WorkspaceTabRecord(
    id: id,
    workspaceId: _workspaceId,
    title: title,
    kind: kind,
    payload: payload,
    createdAt: DateTime.utc(2026, 5, 22),
    updatedAt: DateTime.utc(2026, 5, 22),
  );
}

AgentStatusEntry _agentStatus(
  WorkspaceTabRecord tab, {
  required AgentStatusState state,
}) {
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: AgentType.codex,
    state: state,
    prompt: '',
    updatedAt: DateTime.utc(2026, 5, 22),
    stateStartedAt: DateTime.utc(2026, 5, 22),
  );
}

WorkbenchLayout _splitLayout({
  required String firstTabId,
  required String secondTabId,
  WorkbenchSplitAxis axis = WorkbenchSplitAxis.horizontal,
}) {
  return WorkbenchLayout(
    workspaceId: _workspaceId,
    root: WorkbenchLayoutNode.split(
      axis: axis,
      first: WorkbenchLayoutNode.leaf('group-a'),
      second: WorkbenchLayoutNode.leaf('group-b'),
      ratio: 0.5,
    ),
    groups: <String, WorkbenchPaneGroup>{
      'group-a': WorkbenchPaneGroup(
        id: 'group-a',
        tabIds: <String>[firstTabId],
        activeTabId: firstTabId,
      ),
      'group-b': WorkbenchPaneGroup(
        id: 'group-b',
        tabIds: <String>[secondTabId],
        activeTabId: secondTabId,
      ),
    },
    activeGroupId: 'group-a',
  );
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final List<String> requestedTabIds = <String>[];
  Map<String, bool> get visibilityByTab => <String, bool>{
    for (final entry in _sessions.entries) entry.key: entry.value.visible,
  };
  Map<String, int> get focusRequestsByTab => <String, int>{
    for (final entry in _sessions.entries)
      entry.key: entry.value.requestFocusCalls,
  };

  @override
  Stream<TerminalRuntimeExitEvent> get exits =>
      const Stream<TerminalRuntimeExitEvent>.empty();

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    requestedTabIds.add(tab.id);
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(
        tabId: tab.id,
        workspaceId: workspace.id,
        displayTitle: tab.title,
      ),
    );
  }

  @override
  void closeTab(String tabId) {}

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {}
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({
    required this.tabId,
    required this.workspaceId,
    required this.displayTitle,
  });

  @override
  final String tabId;

  @override
  final String workspaceId;

  @override
  final String displayTitle;

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

  bool visible = false;
  int requestFocusCalls = 0;
  int _visibilityLeaseCount = 0;

  @override
  TerminalVisibilityLease acquireVisibility() {
    _visibilityLeaseCount += 1;
    _setVisible(true);
    return _FakeTerminalVisibilityLease(() {
      if (_visibilityLeaseCount == 0) {
        return;
      }
      _visibilityLeaseCount -= 1;
      _setVisible(_visibilityLeaseCount > 0);
    });
  }

  void _setVisible(bool visible) {
    this.visible = visible;
  }

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
}

final class _FakeTerminalVisibilityLease implements TerminalVisibilityLease {
  _FakeTerminalVisibilityLease(this._onDispose);

  final void Function() _onDispose;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _onDispose();
  }
}

class _SelectedTabAction {
  const _SelectedTabAction(this.groupId, this.tabId);

  final String groupId;
  final String tabId;

  @override
  bool operator ==(Object other) {
    return other is _SelectedTabAction &&
        other.groupId == groupId &&
        other.tabId == tabId;
  }

  @override
  int get hashCode => Object.hash(groupId, tabId);
}

class _MovedTabAction {
  const _MovedTabAction(
    this.tabId,
    this.targetGroupId,
    this.zone, {
    this.index,
  });

  final String tabId;
  final String targetGroupId;
  final WorkbenchDropZone zone;
  final int? index;

  @override
  bool operator ==(Object other) {
    return other is _MovedTabAction &&
        other.tabId == tabId &&
        other.targetGroupId == targetGroupId &&
        other.zone == zone &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(tabId, targetGroupId, zone, index);

  @override
  String toString() =>
      '_MovedTabAction($tabId, $targetGroupId, $zone, index: $index)';
}

class _SplitGroupAction {
  const _SplitGroupAction(this.groupId, this.zone);

  final String groupId;
  final WorkbenchDropZone zone;

  @override
  bool operator ==(Object other) {
    return other is _SplitGroupAction &&
        other.groupId == groupId &&
        other.zone == zone;
  }

  @override
  int get hashCode => Object.hash(groupId, zone);
}

class _UpdatedSplitRatioAction {
  const _UpdatedSplitRatioAction(this.nodePath, this.ratio);

  final List<int> nodePath;
  final double ratio;

  @override
  bool operator ==(Object other) {
    return other is _UpdatedSplitRatioAction &&
        listEquals(other.nodePath, nodePath) &&
        other.ratio == ratio;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(nodePath), ratio);
}
