import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prompt_workspace_controller.g.dart';

class PromptWorkspaceState {
  const PromptWorkspaceState({
    this.projectId,
    this.sourceBranch,
    this.branches = const <String>[],
    this.profiles = const <AgentProfileSummary>[],
    this.profileId,
    this.loading = false,
    this.phase,
    this.error,
    this.creation,
    this.agentTabId,
  });

  final String? projectId;
  final String? sourceBranch;
  final List<String> branches;
  final List<AgentProfileSummary> profiles;
  final String? profileId;
  final bool loading;
  final String? phase;
  final String? error;
  final WorkspaceCreationResult? creation;
  final String? agentTabId;

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
  String? _defaultAgentProfileId;

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
          'Update Alera On This Host To Create A Workspace From A Prompt.',
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
          error: 'Could Not Load Prompt Workspace Options: $error',
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

  Future<void> create({
    required String prompt,
    required Set<String> workspaceBranches,
    String? parentWorkspaceId,
  }) async {
    final projectId = state.projectId;
    final sourceBranch = state.sourceBranch;
    final profileId = state.profileId;
    if (projectId == null ||
        sourceBranch == null ||
        profileId == null ||
        prompt.trim().isEmpty) {
      state = state.copyWith(
        error: 'Complete The Prompt, Project, Branch, And Agent Profile.',
      );
      return;
    }
    state = state.copyWith(
      loading: true,
      phase: 'Generating Workspace Identity',
      clearError: true,
    );
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      WorkspaceCreationResult? creation;
      Object? collisionError;
      for (var attempt = 0; attempt < 2; attempt++) {
        final identityPrompt = attempt == 0
            ? prompt.trim()
            : '${prompt.trim()}\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch.';
        final operationId =
            'mobile-${DateTime.now().microsecondsSinceEpoch}-$attempt';
        _activeOperationId = operationId;
        final GeneratedWorkspaceIdentity identity;
        try {
          identity = await client.generateWorkspaceIdentity(
            operationId: operationId,
            projectId: projectId,
            prompt: identityPrompt,
          );
        } finally {
          if (_activeOperationId == operationId) {
            _activeOperationId = null;
          }
        }
        state = state.copyWith(phase: 'Checking Generated Branch');
        final branches = await client.listBranches(projectId);
        if (workspaceBranches.contains(identity.branchName) ||
            branches.branches.contains(identity.branchName)) {
          collisionError = StateError(
            'The Generated Branch "${identity.branchName}" Already Exists.',
          );
          continue;
        }
        state = state.copyWith(phase: 'Creating Workspace');
        try {
          final created = await client.createManagedWorkspace(
            projectId: projectId,
            branch: identity.branchName,
            sourceBranch: sourceBranch,
            name: identity.workspaceName,
          );
          creation = created;
          final parentId = parentWorkspaceId?.trim();
          if (parentId != null && parentId.isNotEmpty) {
            try {
              await client.linkWorkspaces(
                parentWorkspaceId: parentId,
                childWorkspaceId: created.workspace.id,
              );
            } on Object catch (error) {
              creation = created.withParentLinkError(error);
            }
          }
          break;
        } on Object catch (error) {
          if (attempt == 0 && _looksLikeCollision(error)) {
            collisionError = error;
            continue;
          }
          rethrow;
        }
      }
      if (creation == null) {
        throw collisionError ??
            StateError(
              'AI Text Could Not Generate An Available Workspace Identity.',
            );
      }
      state = state.copyWith(creation: creation, phase: 'Starting Agent');
      final launch = await client.launchAgentProfile(
        workspaceId: creation.workspace.id,
        profileId: profileId,
        prompt: prompt.trim(),
      );
      var completedCreation = creation;
      if (creation.hasDeferredSetup) {
        state = state.copyWith(phase: 'Starting Setup');
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

  Future<void> retryAgent(String prompt) async {
    final creation = state.creation;
    final profileId = state.profileId;
    if (creation == null || profileId == null || prompt.trim().isEmpty) {
      return;
    }
    state = state.copyWith(
      loading: true,
      phase: 'Starting Agent',
      clearError: true,
    );
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      final launch = await client.launchAgentProfile(
        workspaceId: creation.workspace.id,
        profileId: profileId,
        prompt: prompt.trim(),
      );
      var completedCreation = creation;
      if (creation.hasDeferredSetup) {
        state = state.copyWith(phase: 'Starting Setup');
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

  bool _looksLikeCollision(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('already exists') ||
        message.contains('workspace for branch');
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
