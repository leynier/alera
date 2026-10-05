import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_context.g.dart';

/// Names and choices shown instead of raw ids.
class const MobileAutomationContext({
  final List<ProjectSummary> projects = const <ProjectSummary>[],
  final List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
  final List<WorkspaceSectionSummary> sections =
      const <WorkspaceSectionSummary>[],
  final List<AgentProfileSummary> profiles = const <AgentProfileSummary>[],
  final List<WorkspaceTagSummary> tags = const <WorkspaceTagSummary>[],
}) {
  ProjectSummary? project(String? id) =>
      projects.where((item) => item.id == id).firstOrNull;

  WorkspaceSummary? workspace(String? id) =>
      workspaces.where((item) => item.id == id).firstOrNull;

  String projectName(String? id) => project(id)?.name ?? 'Unavailable Project';

  String workspaceName(String? id) =>
      workspace(id)?.name ?? 'Unavailable Workspace';

  String sectionName(String? id) =>
      sections.where((item) => item.id == id).firstOrNull?.name ??
      'Unavailable Section';

  String tagNames(List<String> ids) => <String>[
    for (final id in ids)
      if (tags.where((tag) => tag.id == id).firstOrNull case final tag?)
        tag.name,
  ].join(', ');

  String profileName(String? id) =>
      profiles.where((item) => item.id == id).firstOrNull?.name ??
      'Unavailable Agent Profile';

  String hostName(String? id) =>
      id == null || id.isEmpty || id == 'local' ? 'This Computer' : id;

  bool isGitProject(String? projectId) =>
      project(projectId)?.kind == 'gitRepository';
}

@riverpod
Future<MobileAutomationContext> mobileAutomationContext(
  Ref ref,
  String hostId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final results = await Future.wait<Object>(<Future<Object>>[
    client.listProjects(),
    client.listWorkspaces(),
    client.listAgentProfiles(),
    if (client.supportsWorkspaceSections)
      client.listWorkspaceSections()
    else
      Future<Object>.value(const <WorkspaceSectionSummary>[]),
    client.listWorkspaceTags(),
  ]);
  return MobileAutomationContext(
    projects: results[0] as List<ProjectSummary>,
    workspaces: results[1] as List<WorkspaceSummary>,
    profiles: results[2] as List<AgentProfileSummary>,
    sections: results[3] as List<WorkspaceSectionSummary>,
    tags: results[4] as List<WorkspaceTagSummary>,
  );
}

/// Agent tabs whose native conversation can be resumed.
@riverpod
Future<List<WorkspaceTabSummary>> mobileAutomationConversationTabs(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final tabs = await client.listTabs(workspaceId);
  return tabs
      .where((tab) => (tab.agentNativeSessionId ?? '').trim().isNotEmpty)
      .toList(growable: false);
}

/// Registered project folders of a project, from the runtime checkout list.
@riverpod
Future<List<({String hostId, String path})>> mobileAutomationProjectFolders(
  Ref ref,
  String hostId,
  String projectId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final checkouts = await client.requestList('checkout.list', <String, Object?>{
    'projectId': projectId,
  });
  return <({String hostId, String path})>[
    for (final item in checkouts)
      if (automationJsonMap(item)['kind'] == 'project')
        (
          hostId: automationJsonString(automationJsonMap(item)['hostId']),
          path: automationJsonString(automationJsonMap(item)['path']),
        ),
  ];
}

/// Selects [type] and fills only fields the origin determines without
/// ambiguity. The type itself is always the user's choice.
AutomationDraft chooseMobileAutomationTargetType(
  AutomationDraft draft,
  AutomationTargetType type,
  MobileAutomationContext context, {
  String? originWorkspaceId,
}) {
  final filled = <AutomationDraftField, String>{};
  final origin = context.workspace(
    originWorkspaceId ?? draft.originWorkspaceId,
  );
  switch (type) {
    case AutomationTargetType.freshTab:
    case AutomationTargetType.existingTab:
      if (origin != null) filled[.workspaceId] = origin.id;
    case AutomationTargetType.managedWorkspace:
      if (origin != null && context.isGitProject(origin.projectId)) {
        filled[.workspaceId] = origin.id;
        final branch = origin.branch?.trim();
        if (branch != null && branch.isNotEmpty) filled[.sourceBranch] = branch;
      }
    case AutomationTargetType.projectWorktree:
      if (origin != null && context.isGitProject(origin.projectId)) {
        filled[.projectId] = origin.projectId;
        final branch = origin.branch?.trim();
        if (branch != null && branch.isNotEmpty) filled[.sourceBranch] = branch;
      }
    case AutomationTargetType.projectCheckout:
      if (origin != null) filled[.projectId] = origin.projectId;
  }
  if (type != AutomationTargetType.existingTab &&
      context.profiles.length == 1) {
    filled[.agentProfileId] = context.profiles.single.id;
  }
  final fromContext = filled.keys.toSet();
  // The section is the user's earlier choice, not context, and survives a
  // switch between targets that create workspaces.
  final section = draft.workspaceSectionId;
  if (type.createsWorkspace && section != null) {
    filled[.workspaceSectionId] = section;
  }
  return draft
      .withTargetType(type)
      .copyWith(targetFields: filled, fromContext: fromContext);
}
