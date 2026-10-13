import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
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
}) implements AutomationNameLookup {
  ProjectSummary? project(String? id) =>
      projects.where((item) => item.id == id).firstOrNull;

  WorkspaceSummary? workspace(String? id) =>
      workspaces.where((item) => item.id == id).firstOrNull;

  @override
  String projectName(String? id) => project(id)?.name ?? 'Unavailable Project';

  @override
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

  @override
  String profileName(String? id) =>
      profiles.where((item) => item.id == id).firstOrNull?.name ??
      'Unavailable Agent Profile';

  @override
  String hostName(String? id) =>
      id == null || id.isEmpty || id == 'local' ? 'This Computer' : id;

  /// A worktree can only start from a Git project on the paired computer.
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
