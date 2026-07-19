import 'package:alera_mobile/src/core/json_payload_fields.dart';

enum MobileWorkspaceGroupBy { none, project }

enum MobileWorkbenchSortBy { name, recent, activity }

enum MobileWorkspaceKindFilter { all, defaultOnly, nonDefaultOnly }

/// Runtime-shared sidebar state mirroring the desktop `WorkbenchViewPrefs`
/// fields that also apply on a small screen.
class MobileViewPrefs {
  const MobileViewPrefs({
    this.groupBy = MobileWorkspaceGroupBy.project,
    this.pinnedSectionCollapsed = false,
    this.allSectionCollapsed = false,
    this.projectSort = MobileWorkbenchSortBy.name,
    this.workspaceSort = MobileWorkbenchSortBy.name,
    this.workspaceKindFilter = MobileWorkspaceKindFilter.all,
    this.selectedProjectIds = const <String>{},
    this.selectedTagIds = const <String>{},
    this.collapsedProjectIds = const <String>{},
    this.collapsedParentWorkspaceIds = const <String>{},
    this.revision = 0,
    this.desktopInitialized = false,
  });

  final MobileWorkspaceGroupBy groupBy;
  final bool pinnedSectionCollapsed;
  final bool allSectionCollapsed;
  final MobileWorkbenchSortBy projectSort;
  final MobileWorkbenchSortBy workspaceSort;
  final MobileWorkspaceKindFilter workspaceKindFilter;
  final Set<String> selectedProjectIds;
  final Set<String> selectedTagIds;
  final Set<String> collapsedProjectIds;
  final Set<String> collapsedParentWorkspaceIds;
  final int revision;
  final bool desktopInitialized;

  MobileViewPrefs copyWith({
    MobileWorkspaceGroupBy? groupBy,
    bool? pinnedSectionCollapsed,
    bool? allSectionCollapsed,
    MobileWorkbenchSortBy? projectSort,
    MobileWorkbenchSortBy? workspaceSort,
    MobileWorkspaceKindFilter? workspaceKindFilter,
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
      projectSort: projectSort ?? this.projectSort,
      workspaceSort: workspaceSort ?? this.workspaceSort,
      workspaceKindFilter: workspaceKindFilter ?? this.workspaceKindFilter,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
      collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
      collapsedParentWorkspaceIds:
          collapsedParentWorkspaceIds ?? this.collapsedParentWorkspaceIds,
      revision: revision ?? this.revision,
      desktopInitialized: desktopInitialized ?? this.desktopInitialized,
    );
  }

  factory MobileViewPrefs.fromJson(Map<String, Object?> json) {
    return MobileViewPrefs(
      groupBy:
          json.optionalString('groupBy') == MobileWorkspaceGroupBy.none.name
          ? MobileWorkspaceGroupBy.none
          : MobileWorkspaceGroupBy.project,
      pinnedSectionCollapsed: json['pinnedSectionCollapsed'] == true,
      allSectionCollapsed: json['allSectionCollapsed'] == true,
      projectSort: MobileWorkbenchSortBy.values.byName(
        json.optionalString('projectSort') ?? 'name',
      ),
      workspaceSort: MobileWorkbenchSortBy.values.byName(
        json.optionalString('workspaceSort') ?? 'name',
      ),
      workspaceKindFilter: MobileWorkspaceKindFilter.values.byName(
        json.optionalString('workspaceKindFilter') ?? 'all',
      ),
      selectedProjectIds: json.stringList('selectedProjectIds').toSet(),
      selectedTagIds: json.stringList('selectedTagIds').toSet(),
      collapsedProjectIds: json.stringList('collapsedProjectIds').toSet(),
      collapsedParentWorkspaceIds: json
          .stringList('collapsedParentWorkspaceIds')
          .toSet(),
    );
  }

  factory MobileViewPrefs.fromRecordJson(Map<String, Object?> json) {
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
      'projectSort': projectSort.name,
      'workspaceSort': workspaceSort.name,
      'workspaceKindFilter': workspaceKindFilter.name,
      'selectedProjectIds': selectedProjectIds.toList(),
      'selectedTagIds': selectedTagIds.toList(),
      'collapsedProjectIds': collapsedProjectIds.toList(),
      'collapsedParentWorkspaceIds': collapsedParentWorkspaceIds.toList(),
    };
  }
}
