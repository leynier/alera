import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';

class AgentTaskDispatchException implements Exception {
  const AgentTaskDispatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AgentTaskDispatchService {
  AgentTaskDispatchService({
    required this.catalog,
    required this._findWorkspace,
    required this._findTab,
    required this._activateTab,
    required this._openPersistedTab,
    required this._submitPrompt,
    required this._launchProfile,
    required this._createMutationId,
  });

  final AgentTaskDispatchCatalog catalog;
  final Workspace? Function(String workspaceId) _findWorkspace;
  final WorkspaceTabRecord? Function(String workspaceId, String tabId) _findTab;
  final Future<void> Function(String workspaceId, String tabId) _activateTab;
  final Future<void> Function(String workspaceId, String tabId)
  _openPersistedTab;
  final Future<bool> Function({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
    required String prompt,
  })
  _submitPrompt;
  final Future<AgentProfileLaunchResult> Function({
    required String workspaceId,
    required String profileId,
    required String prompt,
    required String clientMutationId,
  })
  _launchProfile;
  final String Function() _createMutationId;

  Future<AgentTaskDispatchResult> dispatch(
    AgentTaskDispatchRequest request,
    AgentTaskDispatchSelection selection,
  ) {
    final prompt = request.prompt.trim();
    if (prompt.isEmpty) {
      throw const AgentTaskDispatchException('The prompt is empty.');
    }
    return switch (selection) {
      AgentTaskDispatchRunningAgentSelection(:final tabId) => _dispatchToTab(
        workspaceId: request.workspaceId,
        tabId: tabId,
        prompt: prompt,
        openedNewTab: false,
      ),
      AgentTaskDispatchNewTabSelection(:final profileId) => _dispatchToProfile(
        workspaceId: request.workspaceId,
        profileId: profileId,
        prompt: prompt,
      ),
    };
  }

  Future<AgentTaskDispatchResult> dispatchBinding(
    AgentTaskDispatchRequest request,
    AgentTaskDispatchBinding binding,
  ) async {
    final tabId = binding.tabId?.trim();
    if (tabId != null &&
        tabId.isNotEmpty &&
        _findTab(request.workspaceId, tabId) != null) {
      return _dispatchToTab(
        workspaceId: request.workspaceId,
        tabId: tabId,
        prompt: request.prompt,
        openedNewTab: false,
        profileId: binding.profileId,
        label: binding.label,
      );
    }
    final profileId = binding.profileId?.trim();
    if (profileId != null && profileId.isNotEmpty) {
      return _dispatchToProfile(
        workspaceId: request.workspaceId,
        profileId: profileId,
        prompt: request.prompt,
      );
    }
    throw const AgentTaskDispatchException(
      'The selected agent is no longer available.',
    );
  }

  Future<AgentTaskDispatchResult> _dispatchToTab({
    required String workspaceId,
    required String tabId,
    required String prompt,
    required bool openedNewTab,
    String? profileId,
    String? label,
  }) async {
    final workspace = _findWorkspace(workspaceId);
    final tab = _findTab(workspaceId, tabId);
    if (workspace == null || tab == null) {
      throw const AgentTaskDispatchException(
        'The selected agent is no longer available.',
      );
    }
    await _activateTab(workspaceId, tabId);
    if (!await _submitPrompt(workspace: workspace, tab: tab, prompt: prompt)) {
      throw const AgentTaskDispatchException(
        'Could not send the prompt to the agent.',
      );
    }
    final run = _runForTab(tabId);
    return AgentTaskDispatchResult(
      workspaceId: workspaceId,
      tabId: tabId,
      openedNewTab: openedNewTab,
      label: label ?? agentTaskDispatchTabLabel(tab),
      profileId: profileId,
      agentType: run?.status.agentType,
    );
  }

  Future<AgentTaskDispatchResult> _dispatchToProfile({
    required String workspaceId,
    required String profileId,
    required String prompt,
  }) async {
    final profile = _profileById(profileId);
    if (profile == null) {
      throw const AgentTaskDispatchException(
        'The selected agent profile is no longer available.',
      );
    }
    if (_findWorkspace(workspaceId) == null) {
      throw const AgentTaskDispatchException(
        'The workspace is no longer available.',
      );
    }
    final launch = await _launchProfile(
      workspaceId: workspaceId,
      profileId: profileId,
      prompt: prompt,
      clientMutationId: _createMutationId(),
    );
    await _openPersistedTab(workspaceId, launch.tabId);
    return AgentTaskDispatchResult(
      workspaceId: workspaceId,
      tabId: launch.tabId,
      openedNewTab: true,
      label: profile.name,
      profileId: profile.id,
      agentType:
          AgentType.tryParse(launch.agentType) ??
          AgentType.tryParse(profile.agentType),
    );
  }

  WorkspaceAgentRun? _runForTab(String tabId) {
    for (final run in catalog.runningAgents) {
      if (run.tab.id == tabId) {
        return run;
      }
    }
    return null;
  }

  AgentTaskDispatchBinding bindingFor(AgentTaskDispatchSelection selection) {
    return switch (selection) {
      AgentTaskDispatchRunningAgentSelection(:final tabId) =>
        AgentTaskDispatchBinding(tabId: tabId, label: _labelForTab(tabId)),
      AgentTaskDispatchNewTabSelection(:final profileId) =>
        AgentTaskDispatchBinding(
          profileId: profileId,
          label: _profileById(profileId)?.name ?? 'Agent',
        ),
    };
  }

  String _labelForTab(String tabId) {
    final run = _runForTab(tabId);
    return run == null ? 'Agent' : agentTaskDispatchTabLabel(run.tab);
  }

  AgentProfile? _profileById(String profileId) {
    for (final profile in catalog.profiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }
}

String agentTaskDispatchTabLabel(WorkspaceTabRecord tab) {
  final title = tab.title.trim();
  return title.isEmpty ? 'Agent' : title;
}
