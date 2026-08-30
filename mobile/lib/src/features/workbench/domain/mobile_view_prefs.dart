import 'package:alera_mobile/src/core/json_payload_fields.dart';

enum MobileWorkspaceGroupBy { none, project }

enum MobileWorkbenchSortBy { name, recent, activity }

enum MobileWorkspaceKindFilter { all, defaultOnly, nonDefaultOnly }

/// Runtime-shared sidebar state mirroring the desktop `WorkbenchViewPrefs`
/// fields that also apply on a small screen.
class const MobileViewPrefs({
  final MobileWorkspaceGroupBy groupBy = MobileWorkspaceGroupBy.project,
  final bool pinnedSectionCollapsed = false,
  final bool allSectionCollapsed = false,
  final bool showPinnedWorkspacesBelow = true,
  final MobileWorkbenchSortBy projectSort = MobileWorkbenchSortBy.name,
  final MobileWorkbenchSortBy workspaceSort = MobileWorkbenchSortBy.name,
  final MobileWorkspaceKindFilter workspaceKindFilter =
      MobileWorkspaceKindFilter.all,
  final bool showActiveWorkspacesOnly = false,
  final Set<String> selectedProjectIds = const <String>{},
  final Set<String> selectedTagIds = const <String>{},
  final Set<String> collapsedProjectIds = const <String>{},
  final Set<String> collapsedParentWorkspaceIds = const <String>{},
  final int revision = 0,
  final bool desktopInitialized = false,
}) {
  MobileViewPrefs copyWith({
    MobileWorkspaceGroupBy? groupBy,
    bool? pinnedSectionCollapsed,
    bool? allSectionCollapsed,
    bool? showPinnedWorkspacesBelow,
    MobileWorkbenchSortBy? projectSort,
    MobileWorkbenchSortBy? workspaceSort,
    MobileWorkspaceKindFilter? workspaceKindFilter,
    bool? showActiveWorkspacesOnly,
    Set<String>? selectedProjectIds,
    Set<String>? selectedTagIds,
    Set<String>? collapsedProjectIds,
    Set<String>? collapsedParentWorkspaceIds,
    int? revision,
    bool? desktopInitialized,
  }) {
    return MobileViewPrefs(
      groupBy: groupBy ?? this.groupBy,
      pinnedSectionCollapsed:
          pinnedSectionCollapsed ?? this.pinnedSectionCollapsed,
      allSectionCollapsed: allSectionCollapsed ?? this.allSectionCollapsed,
      showPinnedWorkspacesBelow:
          showPinnedWorkspacesBelow ?? this.showPinnedWorkspacesBelow,
      projectSort: projectSort ?? this.projectSort,
      workspaceSort: workspaceSort ?? this.workspaceSort,
      workspaceKindFilter: workspaceKindFilter ?? this.workspaceKindFilter,
      showActiveWorkspacesOnly:
          showActiveWorkspacesOnly ?? this.showActiveWorkspacesOnly,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
      collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
      collapsedParentWorkspaceIds:
          collapsedParentWorkspaceIds ?? this.collapsedParentWorkspaceIds,
      revision: revision ?? this.revision,
      desktopInitialized: desktopInitialized ?? this.desktopInitialized,
    );
  }

  factory fromJson(Map<String, Object?> json) {
    return MobileViewPrefs(
      groupBy:
          json.optionalString('groupBy') == MobileWorkspaceGroupBy.none.name
          ? MobileWorkspaceGroupBy.none
          : MobileWorkspaceGroupBy.project,
      pinnedSectionCollapsed: json['pinnedSectionCollapsed'] == true,
      allSectionCollapsed: json['allSectionCollapsed'] == true,
      showPinnedWorkspacesBelow:
          json['showPinnedWorkspacesBelow'] as bool? ?? true,
      projectSort: MobileWorkbenchSortBy.values.byName(
        json.optionalString('projectSort') ?? 'name',
      ),
      workspaceSort: MobileWorkbenchSortBy.values.byName(
        json.optionalString('workspaceSort') ?? 'name',
      ),
      workspaceKindFilter: MobileWorkspaceKindFilter.values.byName(
        json.optionalString('workspaceKindFilter') ?? 'all',
      ),
      showActiveWorkspacesOnly: json['showActiveWorkspacesOnly'] == true,
      selectedProjectIds: json.stringList('selectedProjectIds').toSet(),
      selectedTagIds: json.stringList('selectedTagIds').toSet(),
      collapsedProjectIds: json.stringList('collapsedProjectIds').toSet(),
      collapsedParentWorkspaceIds: json
          .stringList('collapsedParentWorkspaceIds')
          .toSet(),
    );
  }

  factory fromRecordJson(Map<String, Object?> json) {
    return MobileViewPrefs.fromJson(json.mapValue('prefs')).copyWith(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      desktopInitialized: json['desktopInitialized'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'groupBy': groupBy.name,
      'pinnedSectionCollapsed': pinnedSectionCollapsed,
      'allSectionCollapsed': allSectionCollapsed,
      'showPinnedWorkspacesBelow': showPinnedWorkspacesBelow,
      'projectSort': projectSort.name,
      'workspaceSort': workspaceSort.name,
      'workspaceKindFilter': workspaceKindFilter.name,
      'showActiveWorkspacesOnly': showActiveWorkspacesOnly,
      'selectedProjectIds': selectedProjectIds.toList(),
      'selectedTagIds': selectedTagIds.toList(),
      'collapsedProjectIds': collapsedProjectIds.toList(),
      'collapsedParentWorkspaceIds': collapsedParentWorkspaceIds.toList(),
    };
  }
}
