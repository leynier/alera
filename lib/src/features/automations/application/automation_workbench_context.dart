import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_workbench_context.g.dart';

const String automationLocalHostId = 'local';

/// Names and choices the Automations UI shows instead of raw ids.
class const AutomationWorkbenchContext({
  final List<Project> projects = const <Project>[],
  final List<Workspace> workspaces = const <Workspace>[],
  final List<WorkspaceSection> sections = const <WorkspaceSection>[],
  final List<AgentProfile> profiles = const <AgentProfile>[],
  final List<SshTarget> hosts = const <SshTarget>[],
  final Map<String, List<WorkspaceTabRecord>> tabsByWorkspace =
      const <String, List<WorkspaceTabRecord>>{},
}) {
  Project? project(String? id) =>
      projects.where((item) => item.id == id).firstOrNull;

  Workspace? workspace(String? id) =>
      workspaces.where((item) => item.id == id).firstOrNull;

  WorkspaceSection? section(String? id) =>
      sections.where((item) => item.id == id).firstOrNull;

  AgentProfile? profile(String? id) =>
      profiles.where((item) => item.id == id).firstOrNull;

  String projectName(String? id) => project(id)?.name ?? 'Unavailable Project';

  String workspaceName(String? id) =>
      workspace(id)?.name ?? 'Unavailable Workspace';

  String sectionName(String? id) => section(id)?.name ?? 'Unavailable Section';

  String profileName(String? id) =>
      profile(id)?.name ?? 'Unavailable Agent Profile';

  String hostName(String? id) {
    if (id == null || id.isEmpty || id == automationLocalHostId) {
      return 'This Computer';
    }
    return hosts.where((host) => host.id == id).firstOrNull?.alias ?? id;
  }

  List<Workspace> workspacesOf(String projectId) => workspaces
      .where((item) => item.projectId == projectId)
      .toList(growable: false);

  List<Workspace> workspacesInSection(String sectionId) => workspaces
      .where((item) => item.sectionId == sectionId)
      .toList(growable: false);

  /// Agent tabs whose native conversation can be resumed, which is what an
  /// existing-tab target needs to prove continuity.
  List<WorkspaceTabRecord> conversationTabs(String workspaceId) =>
      (tabsByWorkspace[workspaceId] ?? const <WorkspaceTabRecord>[])
          .where((tab) => automationConversationId(tab) != null)
          .toList(growable: false);
}

String? automationConversationId(WorkspaceTabRecord tab) {
  final value = tab.payload['agentNativeSessionId'];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

@riverpod
AutomationWorkbenchContext automationWorkbenchContext(Ref ref) {
  final workbench = ref.watch(workbenchControllerProvider);
  final profiles =
      ref.watch(agentProfilesProvider).value ?? const <AgentProfile>[];
  final hosts = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
  return AutomationWorkbenchContext(
    projects: workbench.projects,
    workspaces: workbench.workspacesByProject.values
        .expand((items) => items)
        .toList(growable: false),
    sections: workbench.sections,
    profiles: profiles,
    hosts: hosts,
    tabsByWorkspace: workbench.tabsByWorkspace,
  );
}
