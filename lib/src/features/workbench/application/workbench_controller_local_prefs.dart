part of 'workbench_controller.dart';

/// View prefs that stay on this desktop and are never shared with phones.
mixin _WorkbenchControllerLocalPrefs
    on _$WorkbenchController, _WorkbenchControllerViewPrefs {
  void setNewWorkspaceTools(List<WorkspaceTool> tools) {
    final next = WorkspaceTool.uniqueInOrder(tools);
    final current = state.viewPrefs.newWorkspaceTools;
    if (current.length == next.length) {
      var same = true;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != next[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _updateViewPrefs(state.viewPrefs.copyWith(newWorkspaceTools: next));
  }

  /// Remembers the Home composer selection.
  void setHomeComposerPrefs(HomeComposerPrefs prefs) {
    if (state.viewPrefs.homeComposer == prefs) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(homeComposer: prefs));
  }
}
