part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceDetails
    on _$WorkbenchController, _WorkbenchControllerViewPrefs {
  void toggleWorkspaceDetails(String workspaceId) {
    final hidden = Set<String>.from(state.viewPrefs.workspaceDetailsHiddenIds);
    if (!hidden.add(workspaceId)) hidden.remove(workspaceId);
    _updateViewPrefs(
      state.viewPrefs.copyWith(workspaceDetailsHiddenIds: hidden),
    );
  }

  void toggleWorkspaceDetailsAgents(String workspaceId) {
    final expanded = Set<String>.from(
      state.viewPrefs.workspaceDetailsAgentsExpandedIds,
    );
    if (!expanded.add(workspaceId)) expanded.remove(workspaceId);
    _updateViewPrefs(
      state.viewPrefs.copyWith(workspaceDetailsAgentsExpandedIds: expanded),
    );
  }

  void toggleWorkspaceDetailsAgentGroup(
    String workspaceId,
    WorkspacePanelTree tree,
  ) {
    final collapsed = Set<String>.from(
      state.viewPrefs.workspaceDetailsAgentGroupsCollapsed,
    );
    final key = workspaceDetailsAgentGroupKey(workspaceId, tree);
    if (!collapsed.add(key)) collapsed.remove(key);
    _updateViewPrefs(
      state.viewPrefs.copyWith(workspaceDetailsAgentGroupsCollapsed: collapsed),
    );
  }

  void setWorkspaceComparisonBase(
    String workspaceId,
    String root,
    String? base,
  ) {
    final bases = Map<String, String>.from(
      state.viewPrefs.workspaceComparisonBases,
    );
    final key = '$workspaceId:$root';
    if (base == null) {
      bases.remove(key);
    } else {
      bases[key] = base;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(workspaceComparisonBases: bases));
  }
}
