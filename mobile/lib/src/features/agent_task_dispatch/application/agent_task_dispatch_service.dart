import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';

import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';

/// Sends a prompt to a running workspace agent or launches a profile tab.
///
/// Callers, including file comments and pull request Watch and Fix, own the
/// prompt. This type does not talk to Riverpod so tests can stub the host.
class AgentTaskDispatchService {
  AgentTaskDispatchService({
    required this.workspaceId,
    required this._terminalClient,
    required Future<String> Function(String profileId, String prompt)
    launchProfile,
    required this._tabs,
    required this._runningAgents,
  }) : _launchProfileTab = launchProfile;

  final String workspaceId;
  final MobileTerminalClient _terminalClient;
  final Future<String> Function(String profileId, String prompt)
  _launchProfileTab;
  final List<WorkspaceTabSummary> Function() _tabs;
  final List<AgentPresenceSummary> Function() _runningAgents;

  Future<AgentTaskDispatchResult> dispatchTarget(
    WorkspaceAgentCommentTarget target,
    String prompt,
  ) {
    return dispatchBinding(agentTaskDispatchBindingFor(target), prompt);
  }

  Future<AgentTaskDispatchResult> dispatchBinding(
    AgentTaskDispatchBinding binding,
    String prompt,
  ) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      throw const AgentTaskDispatchException('The prompt is empty.');
    }
    final tabId = binding.tabId?.trim();
    if (tabId != null && tabId.isNotEmpty) {
      final sessionId = _sessionIdForTab(tabId);
      if (sessionId != null) {
        await _writeToSession(sessionId, trimmed);
        return AgentTaskDispatchResult(
          tabId: tabId,
          openedNewTab: false,
          label: binding.label?.trim().isNotEmpty == true
              ? binding.label!.trim()
              : 'Agent',
          profileId: binding.profileId,
        );
      }
    }
    final profileId = binding.profileId?.trim();
    if (profileId != null && profileId.isNotEmpty) {
      return _launchProfile(
        profileId: profileId,
        prompt: trimmed,
        label: binding.label,
      );
    }
    throw const AgentTaskDispatchException(
      'The selected agent is no longer available.',
    );
  }

  Future<AgentTaskDispatchResult> _launchProfile({
    required String profileId,
    required String prompt,
    String? label,
  }) async {
    final tabId = await _launchProfileTab(profileId, prompt);
    return AgentTaskDispatchResult(
      tabId: tabId,
      openedNewTab: true,
      label: (label == null || label.trim().isEmpty) ? 'Agent' : label.trim(),
      profileId: profileId,
    );
  }

  String? _sessionIdForTab(String tabId) {
    for (final tab in _tabs()) {
      if (tab.id == tabId) {
        return tab.terminalSessionId;
      }
    }
    for (final agent in _runningAgents()) {
      if (agent.tabId == tabId && agent.workspaceId == workspaceId) {
        return agent.terminalSessionId;
      }
    }
    return null;
  }

  Future<void> _writeToSession(String sessionId, String prompt) async {
    final delivery = TerminalComposeDelivery.forText(
      prompt,
      withEnter: true,
      hostSupportsDeferredInput: _terminalClient.supportsDeferredTerminalInput,
    );
    await _terminalClient.writeTerminal(
      sessionId,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
      deferredEnter: delivery.deferredEnter,
    );
  }
}
