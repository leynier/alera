import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// Caller-owned work to send through the shared agent picker.
///
/// This feature owns listing running agents, opening a profile tab, and
/// injecting [prompt]. Callers, including file and diff comments, supply the
/// prompt and any surrounding copy.
class const AgentTaskDispatchRequest({
  required final String workspaceId,
  required final String prompt,
  final String title = 'Send To Agent',
  final String? message,
});

/// Durable target so a later dispatch can reuse the same agent without the
/// picker. [tabId] is the live terminal when known; [profileId] is how a new
/// tab is opened if that terminal is gone.
class const AgentTaskDispatchBinding({
  final String? tabId,
  final String? profileId,
  final String? label,
});

sealed class const AgentTaskDispatchSelection();

class const AgentTaskDispatchRunningAgentSelection({
  required final String tabId,
}) extends AgentTaskDispatchSelection;

class const AgentTaskDispatchNewTabSelection({required final String profileId})
    extends AgentTaskDispatchSelection;

class const AgentTaskDispatchResult({
  required final String workspaceId,
  required final String tabId,
  required final bool openedNewTab,
  required final String label,
  final String? profileId,
  final AgentType? agentType,
}) {
  AgentTaskDispatchBinding get binding => AgentTaskDispatchBinding(
    tabId: tabId,
    profileId: profileId,
    label: label,
  );
}

class const AgentTaskDispatchCatalog({
  final List<WorkspaceAgentRun> runningAgents = const <WorkspaceAgentRun>[],
  final List<AgentProfile> profiles = const <AgentProfile>[],
  final String? defaultProfileId,
}) {
  bool get isEmpty => runningAgents.isEmpty && profiles.isEmpty;
}

AgentTaskDispatchCatalog buildAgentTaskDispatchCatalog({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
  required List<AgentProfile> profiles,
  String? defaultProfileId,
}) {
  return AgentTaskDispatchCatalog(
    runningAgents: visibleWorkspaceAgentRuns(
      tabs: tabs,
      agentStatuses: agentStatuses,
    ),
    profiles: List<AgentProfile>.unmodifiableOf(profiles),
    defaultProfileId: defaultProfileId,
  );
}
