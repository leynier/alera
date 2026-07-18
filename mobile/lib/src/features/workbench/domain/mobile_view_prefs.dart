import 'package:alera_mobile/src/core/json_payload_fields.dart';

enum MobileWorkspaceGroupBy { none, project }

/// Per-host sidebar view state persisted on the phone. Mirrors the desktop
/// `WorkbenchViewPrefs` surface that matters on a small screen.
class MobileViewPrefs {
  const MobileViewPrefs({
    this.groupBy = MobileWorkspaceGroupBy.project,
    this.pinnedSectionCollapsed = false,
    this.collapsedProjectIds = const <String>{},
    this.collapsedParentWorkspaceIds = const <String>{},
  });

  final MobileWorkspaceGroupBy groupBy;
  final bool pinnedSectionCollapsed;
  final Set<String> collapsedProjectIds;
  final Set<String> collapsedParentWorkspaceIds;

  MobileViewPrefs copyWith({
    MobileWorkspaceGroupBy? groupBy,
    bool? pinnedSectionCollapsed,
    Set<String>? collapsedProjectIds,
    Set<String>? collapsedParentWorkspaceIds,
  }) {
    return MobileViewPrefs(
      groupBy: groupBy ?? this.groupBy,
      pinnedSectionCollapsed:
          pinnedSectionCollapsed ?? this.pinnedSectionCollapsed,
      collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
      collapsedParentWorkspaceIds:
          collapsedParentWorkspaceIds ?? this.collapsedParentWorkspaceIds,
    );
  }

  factory MobileViewPrefs.fromJson(Map<String, Object?> json) {
    return MobileViewPrefs(
      groupBy:
          json.optionalString('groupBy') == MobileWorkspaceGroupBy.none.name
          ? MobileWorkspaceGroupBy.none
          : MobileWorkspaceGroupBy.project,
      pinnedSectionCollapsed: json['pinnedSectionCollapsed'] == true,
      collapsedProjectIds: json.stringList('collapsedProjectIds').toSet(),
      collapsedParentWorkspaceIds: json
          .stringList('collapsedParentWorkspaceIds')
          .toSet(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'groupBy': groupBy.name,
      'pinnedSectionCollapsed': pinnedSectionCollapsed,
      'collapsedProjectIds': collapsedProjectIds.toList(),
      'collapsedParentWorkspaceIds': collapsedParentWorkspaceIds.toList(),
    };
  }
}
