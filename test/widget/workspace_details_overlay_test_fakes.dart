part of 'workspace_details_overlay_test.dart';

class _Workbench extends WorkbenchController {
  _Workbench([this.seed = const WorkbenchState(activeWorkspaceId: 'w')]);
  final WorkbenchState seed;
  final selectedTabs = <String>[];
  final selectedWorkspaces = <String>[];
  final sleptWorkspaces = <String>[];
  @override
  Future<void> sleepWorkspace(Workspace workspace) async =>
      sleptWorkspaces.add(workspace.id);
  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async => selectedWorkspaces.add(workspace.id);
  @override
  WorkbenchState build() => seed;
  @override
  Future<void> selectWorkspaceTab({
    required String workspaceId,
    required String tabId,
  }) async => selectedTabs.add(tabId);
  @override
  void setRightSidebarVisible(bool visible) => state = state.copyWith(
    viewPrefs: state.viewPrefs.copyWith(rightSidebarVisible: visible),
  );
  @override
  void setContextPanelTab(WorkbenchContextPanelTab tab) =>
      state = state.copyWith(
        viewPrefs: state.viewPrefs.copyWith(activeContextPanelTab: tab),
      );
  @override
  void toggleWorkspaceDetails(String id) {
    final hidden = {...state.viewPrefs.workspaceDetailsHiddenIds};
    if (!hidden.add(id)) hidden.remove(id);
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceDetailsHiddenIds: hidden),
    );
  }
}

class _Reviews extends WorkspacePullRequestController {
  _Reviews(this.snapshot);
  final WorkspacePullRequestState snapshot;
  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async => snapshot;
  @override
  void attachPanel() {}
  @override
  void detachPanel() {}
}

int _fetches = 0;

class _Sources extends WorkspaceSourceControlController {
  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) async =>
      details.sourceControl;
  @override
  Future<void> fetch() async => _fetches++;
}

class _Runtime implements TerminalRuntime {
  final focused = <String>[];
  @override
  TerminalSessionHandle? peekSession(String tabId) => null;
  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    focused.add(tab.id);
    return _ToolbarSession();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
