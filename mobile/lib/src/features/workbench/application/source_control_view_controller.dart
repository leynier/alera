import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_view_controller.g.dart';

/// Per-workspace Source Control view state that is not worth sharing across
/// devices: which nodes are collapsed and the file filter. The view and group
/// modes live in the shared runtime view prefs instead.
class const SourceControlViewState({
  final Set<String> collapsedKeys = const <String>{},
  final String filter = '',
  final bool filterVisible = false,
});

@riverpod
class SourceControlViewController extends _$SourceControlViewController {
  @override
  SourceControlViewState build(String hostId, String workspaceId) =>
      const SourceControlViewState();

  void toggleCollapsed(String key) {
    final next = <String>{...state.collapsedKeys};
    if (!next.remove(key)) {
      next.add(key);
    }
    state = SourceControlViewState(
      collapsedKeys: next,
      filter: state.filter,
      filterVisible: state.filterVisible,
    );
  }

  /// Collapses every key when any is expanded, else expands everything, like
  /// the desktop Collapse All.
  void toggleAllCollapsed(Set<String> keys) {
    final allCollapsed =
        keys.isNotEmpty && keys.every(state.collapsedKeys.contains);
    state = SourceControlViewState(
      collapsedKeys: allCollapsed ? const <String>{} : keys,
      filter: state.filter,
      filterVisible: state.filterVisible,
    );
  }

  void setFilter(String value) {
    state = SourceControlViewState(
      collapsedKeys: state.collapsedKeys,
      filter: value,
      filterVisible: state.filterVisible,
    );
  }

  void toggleFilterVisible() {
    final visible = !state.filterVisible;
    state = SourceControlViewState(
      collapsedKeys: state.collapsedKeys,
      // Hiding the field must not leave a filter applied that nobody can see.
      filter: visible ? state.filter : '',
      filterVisible: visible,
    );
  }
}
