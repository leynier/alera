enum WorkbenchGroupBy { none, project }

enum WorkbenchSortBy { name, recent }

WorkbenchGroupBy _groupByFromWire(Object? value) {
  if (value is String) {
    for (final option in WorkbenchGroupBy.values) {
      if (option.name == value) {
        return option;
      }
    }
  }
  return WorkbenchGroupBy.project;
}

WorkbenchSortBy _sortByFromWire(Object? value, WorkbenchSortBy fallback) {
  if (value is String) {
    for (final option in WorkbenchSortBy.values) {
      if (option.name == value) {
        return option;
      }
    }
  }
  return fallback;
}

Set<String> _idsFromWire(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return <String>{
    for (final entry in value)
      if (entry is String && entry.isNotEmpty) entry,
  };
}

class WorkbenchViewPrefs {
  const WorkbenchViewPrefs({
    required this.groupBy,
    required this.projectSort,
    required this.workspaceSort,
    required this.selectedProjectIds,
    required this.collapsedProjectIds,
    required this.expandedWorkspaceIds,
  });

  final WorkbenchGroupBy groupBy;
  final WorkbenchSortBy projectSort;
  final WorkbenchSortBy workspaceSort;

  /// Projects the user has explicitly added to the visibility filter. When the
  /// set is empty the sidebar shows every project; when non-empty it shows
  /// only the listed ones (positive selection, Orca-style).
  final Set<String> selectedProjectIds;
  final Set<String> collapsedProjectIds;

  /// Workspaces whose sidebar terminal-tab list is currently expanded.
  /// Activating a workspace adds it to this set so terminal tabs are visible by
  /// default; the per-row chevron lets the user toggle membership without
  /// changing the active selection.
  final Set<String> expandedWorkspaceIds;

  static const WorkbenchViewPrefs defaults = WorkbenchViewPrefs(
    groupBy: WorkbenchGroupBy.project,
    projectSort: WorkbenchSortBy.name,
    workspaceSort: WorkbenchSortBy.name,
    selectedProjectIds: <String>{},
    collapsedProjectIds: <String>{},
    expandedWorkspaceIds: <String>{},
  );

  WorkbenchViewPrefs copyWith({
    WorkbenchGroupBy? groupBy,
    WorkbenchSortBy? projectSort,
    WorkbenchSortBy? workspaceSort,
    Set<String>? selectedProjectIds,
    Set<String>? collapsedProjectIds,
    Set<String>? expandedWorkspaceIds,
  }) {
    return WorkbenchViewPrefs(
      groupBy: groupBy ?? this.groupBy,
      projectSort: projectSort ?? this.projectSort,
      workspaceSort: workspaceSort ?? this.workspaceSort,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
      expandedWorkspaceIds: expandedWorkspaceIds ?? this.expandedWorkspaceIds,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'groupBy': groupBy.name,
      'projectSort': projectSort.name,
      'workspaceSort': workspaceSort.name,
      'selectedProjectIds': selectedProjectIds.toList(growable: false),
      'collapsedProjectIds': collapsedProjectIds.toList(growable: false),
      'expandedWorkspaceIds': expandedWorkspaceIds.toList(growable: false),
    };
  }

  factory WorkbenchViewPrefs.fromJson(Map<String, Object?> json) {
    // Back-compat: earlier builds stored "hiddenProjectIds" (negative
    // selection) and "terminalsCollapsedWorkspaceIds" (inverse of the current
    // expansion semantics). Discard both silently so users land on a sane
    // default view rather than inheriting state with inverted meaning.
    final selected = json.containsKey('selectedProjectIds')
        ? _idsFromWire(json['selectedProjectIds'])
        : const <String>{};
    final expanded = json.containsKey('expandedWorkspaceIds')
        ? _idsFromWire(json['expandedWorkspaceIds'])
        : const <String>{};
    return WorkbenchViewPrefs(
      groupBy: _groupByFromWire(json['groupBy']),
      projectSort: _sortByFromWire(json['projectSort'], WorkbenchSortBy.name),
      workspaceSort: _sortByFromWire(
        json['workspaceSort'],
        WorkbenchSortBy.name,
      ),
      selectedProjectIds: selected,
      collapsedProjectIds: _idsFromWire(json['collapsedProjectIds']),
      expandedWorkspaceIds: expanded,
    );
  }
}
