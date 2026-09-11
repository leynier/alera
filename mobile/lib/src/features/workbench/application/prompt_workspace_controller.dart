import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prompt_workspace_controller.g.dart';

class const PromptWorkspaceState({
  final String? projectId,
  final String? sourceBranch,
  final List<String> branches = const <String>[],
  final List<AgentProfileSummary> profiles = const <AgentProfileSummary>[],
  final String? profileId,
  final bool loading = false,
  final String? phase,
  final String? error,
  final WorkspaceCreationResult? creation,
  final String? agentTabId,
}) {
  PromptWorkspaceState copyWith({
    String? projectId,
    String? sourceBranch,
    List<String>? branches,
    List<AgentProfileSummary>? profiles,
    String? profileId,
    bool? loading,
    String? phase,
    String? error,
    WorkspaceCreationResult? creation,
    String? agentTabId,
    bool clearSourceBranch = false,
    bool clearPhase = false,
    bool clearError = false,
    bool clearCreation = false,
    bool clearAgentTabId = false,
  }) {
    return PromptWorkspaceState(
      projectId: projectId ?? this.projectId,
      sourceBranch: clearSourceBranch
          ? null
          : (sourceBranch ?? this.sourceBranch),
      branches: branches ?? this.branches,
      profiles: profiles ?? this.profiles,
      profileId: profileId ?? this.profileId,
      loading: loading ?? this.loading,
      phase: clearPhase ? null : (phase ?? this.phase),
      error: clearError ? null : (error ?? this.error),
      creation: clearCreation ? null : (creation ?? this.creation),
      agentTabId: clearAgentTabId ? null : (agentTabId ?? this.agentTabId),
    );
  }
}

@riverpod
class PromptWorkspaceController extends _$PromptWorkspaceController {
  String? _activeOperationId;
  String? _agentLaunchMutationId;
  bool? _originalAgentLaunchWasIdempotent;
  String? _defaultAgentProfileId;
  var _creating = false;

  @override
  PromptWorkspaceState build(String hostId) {
    return const PromptWorkspaceState();
  }

  Future<void> selectProject(
    String projectId, {
    String? defaultAgentProfileId,
  }) async {
    _defaultAgentProfileId = defaultAgentProfileId;
    state = state.copyWith(
      projectId: projectId,
      branches: const <String>[],
      clearSourceBranch: true,
      loading: true,
      clearError: true,
    );
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (!client.supportsPromptWorkspaceCreation) {
        throw UnsupportedError(
          'Update Alera on this host to create a workspace from a prompt.',
        );
      }
      final results = await Future.wait<Object>([
        client.listBranches(projectId),
        client.listAgentProfiles(),
      ]);
      if (state.projectId != projectId) {
        return;
      }
      final branches = (results[0] as ProjectBranches).branches;
      final profiles = results[1] as List<AgentProfileSummary>;
      state = state.copyWith(
        branches: branches,
        sourceBranch: _defaultBranch(branches),
        profiles: profiles,
        profileId: state.profileId ?? _preferredProfileId(profiles),
        loading: false,
      );
    } on Object catch (error) {
      if (state.projectId == projectId) {
        state = state.copyWith(
          loading: false,
          error: 'Could not load prompt workspace options: $error',
        );
      }
    }
  }

  void selectSourceBranch(String branch) {
    state = state.copyWith(sourceBranch: branch);
  }

  void selectProfile(String profileId) {
    state = state.copyWith(profileId: profileId);
  }

  Future<WorkspaceCreationResult> create({
    required String prompt,
    required Set<String> workspaceBranches,
    String? parentWorkspaceId,
    String? projectId,
    String? sourceBranch,
    String? profileId,
  }) async {
    if (_creating) {
      throw StateError('Workspace creation is already running.');
    }
    _creating = true;
    try {
      return await _create(
        prompt: prompt,
        workspaceBranches: workspaceBranches,
        parentWorkspaceId: parentWorkspaceId,
        projectId: projectId,
        sourceBranch: sourceBranch,
        profileId: profileId,
      );
    } finally {
      _creating = false;
    }
  }

  Future<WorkspaceCreationResult> _create({
    required String prompt,
    required Set<String> workspaceBranches,
    String? parentWorkspaceId,
    String? projectId,
    String? sourceBranch,
    String? profileId,
  }) async {
    if (projectId != null && state.projectId != projectId) {
      await selectProject(projectId, defaultAgentProfileId: profileId);
    }
    if (sourceBranch != null) {
      selectSourceBranch(sourceBranch);
    }
    if (profileId != null) {
      selectProfile(profileId);
    }
    final resolvedProjectId = projectId ?? state.projectId;
    final resolvedSourceBranch = sourceBranch ?? state.sourceBranch;
    final resolvedProfileId = profileId ?? state.profileId;
    if (resolvedProjectId == null ||
        resolvedSourceBranch == null ||
        resolvedProfileId == null ||
        prompt.trim().isEmpty) {
      const message =
          'Complete the prompt, project, branch, and agent profile.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    state = state.copyWith(
      loading: true,
      phase: 'Generating workspace identity',
      clearError: true,
    );
    _agentLaunchMutationId = null;
    _originalAgentLaunchWasIdempotent = null;
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      _originalAgentLaunchWasIdempotent =
          client.supportsIdempotentAgentProfileLaunch;
      final clientMutationId = _agentLaunchMutationId ??=
          'mobile-agent-launch-${DateTime.now().microsecondsSinceEpoch}';
      final outcome = await runPromptWorkspaceCreate(
        client: client,
        loadTerminalClient: () =>
            ref.read(terminalClientProvider(hostId).future),
        request: PromptWorkspaceCreateRequest(
          hostId: hostId,
          prompt: prompt,
          projectId: resolvedProjectId,
          sourceBranch: resolvedSourceBranch,
          profileId: resolvedProfileId,
          workspaceBranches: workspaceBranches,
          parentWorkspaceId: parentWorkspaceId,
        ),
        clientMutationId: clientMutationId,
        onPhase: (phase) {
          state = state.copyWith(phase: phase);
        },
        onOperationId: (operationId) {
          _activeOperationId = operationId;
        },
        onWorkspaceCreated: (creation) {
          state = state.copyWith(creation: creation, phase: 'Starting agent');
        },
      );
      state = state.copyWith(
        creation: outcome.creation,
        loading: false,
        agentTabId: outcome.agentTabId,
        clearPhase: true,
      );
      return outcome.creation;
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        clearPhase: true,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> retryAgent(String prompt) async {
    final creation = state.creation;
    final profileId = state.profileId;
    if (creation == null || profileId == null || prompt.trim().isEmpty) {
      return;
    }
    state = state.copyWith(
      loading: true,
      phase: 'Starting agent',
      clearError: true,
    );
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (_originalAgentLaunchWasIdempotent != true ||
          !client.supportsIdempotentAgentProfileLaunch) {
        throw UnsupportedError(
          'Update Alera on this host before retrying agent launch safely.',
        );
      }
      final clientMutationId = _agentLaunchMutationId;
      if (clientMutationId == null) {
        throw StateError('The original agent launch identity is unavailable.');
      }
      final launch = await client.launchAgentProfile(
        workspaceId: creation.workspace.id,
        profileId: profileId,
        prompt: prompt.trim(),
        clientMutationId: clientMutationId,
      );
      var completedCreation = creation;
      if (creation.hasDeferredSetup) {
        state = state.copyWith(phase: 'Starting setup');
        final terminalClient = await ref.read(
          terminalClientProvider(hostId).future,
        );
        completedCreation = await launchDeferredWorkspaceSetup(
          terminalClient,
          creation,
        );
      }
      state = state.copyWith(
        creation: completedCreation,
        loading: false,
        agentTabId: launch.tabId,
        clearPhase: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        clearPhase: true,
        error: error.toString(),
      );
    }
  }

  void resetForAnother() {
    _agentLaunchMutationId = null;
    _originalAgentLaunchWasIdempotent = null;
    state = state.copyWith(
      loading: false,
      clearPhase: true,
      clearError: true,
      clearCreation: true,
      clearAgentTabId: true,
    );
  }

  Future<void> cancelGeneration() async {
    final operationId = _activeOperationId;
    if (operationId == null) {
      return;
    }
    final client = await ref.read(workspaceClientProvider(hostId).future);
    await client.cancelWorkspaceIdentity(operationId);
  }

  String? _defaultBranch(List<String> branches) {
    for (final preferred in const <String>[
      'main',
      'origin/main',
      'master',
      'origin/master',
    ]) {
      if (branches.contains(preferred)) {
        return preferred;
      }
    }
    return branches.firstOrNull;
  }

  String? _preferredProfileId(List<AgentProfileSummary> profiles) {
    final defaultId = _defaultAgentProfileId;
    if (defaultId != null) {
      for (final profile in profiles) {
        if (profile.id == defaultId) {
          return profile.id;
        }
      }
    }
    return profiles.firstOrNull?.id;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
