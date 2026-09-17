import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';

/// Caller-owned work to send through the shared running-agent-or-profile picker.
class const AgentTaskDispatchRequest({
  required final String hostId,
  required final String workspaceId,
  required final String prompt,
  final String title = 'Send To Agent',
  final String? message,
});

/// Durable target so a later watch dispatch can reuse the same agent.
///
/// [tabId] is the live terminal when known; [profileId] opens a new tab if
/// that terminal is gone.
class const AgentTaskDispatchBinding({
  final String? tabId,
  final String? profileId,
  final String? label,
});

class const AgentTaskDispatchResult({
  required final String tabId,
  required final bool openedNewTab,
  required final String label,
  final String? profileId,
}) {
  AgentTaskDispatchBinding get binding => AgentTaskDispatchBinding(
    tabId: tabId,
    profileId: profileId,
    label: label,
  );
}

class AgentTaskDispatchException implements Exception {
  const AgentTaskDispatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

AgentTaskDispatchBinding agentTaskDispatchBindingFor(
  WorkspaceAgentCommentTarget target,
) {
  return switch (target) {
    RunningAgentCommentTarget(:final agent) => AgentTaskDispatchBinding(
      tabId: agent.tabId,
      label: agentTaskDispatchAgentLabel(agent),
    ),
    AgentProfileCommentTarget(:final profile) => AgentTaskDispatchBinding(
      profileId: profile.id,
      label: profile.name,
    ),
  };
}

String agentTaskDispatchAgentLabel(AgentPresenceSummary agent) {
  final title = agent.title.trim();
  return title.isEmpty ? agent.agentType : title;
}

String agentTaskDispatchProfileLabel(AgentProfileSummary profile) =>
    profile.name;
