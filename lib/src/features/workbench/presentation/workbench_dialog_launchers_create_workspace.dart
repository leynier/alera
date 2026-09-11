part of 'workbench_dialog_launchers.dart';

/// Opens the create-workspace dialog for the active Git project. Linked
/// workspaces require a Git project, so folder-only projects are filtered out.
Future<void> showCreateWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  Project? initialProject,
  ManualWorkspaceCreateRequest? retryManual,
  PromptWorkspaceCreateRequest? retryPrompt,
  String? retryError,
  String? retryJobId,
}) async {
  var remainingRetryJobId = retryJobId;
  final jobs = ref.read(backgroundSetupJobsProvider.notifier);
  jobs.beginForm();
  try {
    await _runCreateWorkspaceFlow(
      context,
      ref,
      initialProject: initialProject,
      retryManual: retryManual,
      retryPrompt: retryPrompt,
      retryError: retryError,
      remainingRetryJobId: remainingRetryJobId,
    );
  } finally {
    jobs.endForm();
  }
}

Future<void> _runCreateWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  Project? initialProject,
  ManualWorkspaceCreateRequest? retryManual,
  PromptWorkspaceCreateRequest? retryPrompt,
  String? retryError,
  String? remainingRetryJobId,
}) async {
  final controller = ref.read(workbenchControllerProvider.notifier);
  final state = ref.read(workbenchControllerProvider);
  final projects = state.projects
      .where((project) => project.supportsLinkedWorkspaces)
      .toList(growable: false);
  final parentCandidates = <WorkspaceParentCandidate>[
    for (final project in state.projects)
      for (final workspace in state.workspacesFor(project.id))
        if (workspace.isActive)
          WorkspaceParentCandidate(project: project, workspace: workspace),
  ];

  final resolvedInitialProject =
      retryManual?.project ??
      retryPrompt?.project ??
      (initialProject?.supportsLinkedWorkspaces == true
          ? initialProject
          : null);

  List<AgentProfile> profiles;
  try {
    profiles = await ref.read(agentProfilesProvider.future);
  } catch (_) {
    profiles = const <AgentProfile>[];
  }
  final runtime = PromptWorkspaceRuntimeClient(
    ref.read(runtimeHostClientProvider),
    beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
  );
  final sshTargets = await _loadSshTargets(ref);
  if (!context.mounted) {
    return;
  }
  await _showCreateWorkspaceDialogs(
    context,
    ref,
    controller: controller,
    projects: projects,
    parentCandidates: parentCandidates,
    sshTargets: sshTargets,
    resolvedInitialProject: resolvedInitialProject,
    profiles: profiles,
    runtime: runtime,
    retryManual: retryManual,
    retryPrompt: retryPrompt,
    retryError: retryError,
    remainingRetryJobId: remainingRetryJobId,
  );
}

Future<void> _showCreateWorkspaceDialogs(
  BuildContext context,
  WidgetRef ref, {
  required WorkbenchController controller,
  required List<Project> projects,
  required List<WorkspaceParentCandidate> parentCandidates,
  required List<SshTarget> sshTargets,
  required Project? resolvedInitialProject,
  required List<AgentProfile> profiles,
  required PromptWorkspaceRuntimeClient runtime,
  ManualWorkspaceCreateRequest? retryManual,
  PromptWorkspaceCreateRequest? retryPrompt,
  String? retryError,
  String? remainingRetryJobId,
}) async {
  var boundJobId = remainingRetryJobId;
  if (retryManual != null) {
    await _showManualWorkspaceDialog(
      context,
      ref,
      controller: controller,
      projects: projects,
      parentCandidates: parentCandidates,
      sshTargets: sshTargets,
      resolvedInitialProject: resolvedInitialProject,
      retryManual: retryManual,
      retryError: retryError,
      retryJobId: boundJobId,
    );
    return;
  }
  final promptResult = await showDialog<PromptWorkspaceDialogResult>(
    context: context,
    builder: (_) => PromptWorkspaceDialog(
      projects: projects,
      agentProfiles: profiles,
      sshTargets: sshTargets,
      defaultAgentProfileId:
          retryPrompt?.profileId ??
          ref.read(settingsControllerProvider).agents.defaultAgentProfileId,
      initialProject: resolvedInitialProject,
      initialPrompt: retryPrompt?.prompt,
      initialSourceBranch: retryPrompt?.sourceBranch,
      initialParentWorkspaceId: retryPrompt?.parentWorkspaceId,
      initialHostId: retryPrompt?.hostId,
      initialError: retryPrompt == null ? null : retryError,
      enqueuePrompt: (request) {
        boundJobId ??= const Uuid().v4();
        final done = ref
            .read(backgroundSetupJobsProvider.notifier)
            .enqueuePromptWorkspace(request, jobId: boundJobId);
        if (done == null) {
          return null;
        }
        return done.then((_) {
          boundJobId = const Uuid().v4();
        });
      },
      loadBranches: controller.listSourceBranches,
      checkBranchExists: (project, branchName) {
        return ref
            .read(gitBackendProvider)
            .branchExists(project.repoPath, branchName);
      },
      workspaceBranches: (project) {
        return ref
            .read(workbenchControllerProvider)
            .workspacesFor(project.id)
            .where((workspace) => workspace.isActive)
            .map((workspace) => workspace.branch?.trim() ?? '')
            .where((branch) => branch.isNotEmpty)
            .toSet();
      },
      parentWorkspaces: <Workspace>[
        for (final candidate in parentCandidates) candidate.workspace,
      ],
      generateIdentity: runtime.generateIdentity,
      cancelGeneration: runtime.cancel,
      createWorkspace:
          ({
            required project,
            required sourceBranch,
            required newBranchName,
            required name,
            parentWorkspaceId,
            hostId,
          }) {
            return controller.createWorkspaceForPrompt(
              project: project,
              sourceBranch: sourceBranch,
              newBranchName: newBranchName,
              name: name,
              parentWorkspaceId: parentWorkspaceId,
              hostId: hostId,
            );
          },
      launchAgent: runtime.launchAgent,
      supportsIdempotentAgentLaunch: () =>
          runtime.supportsIdempotentAgentLaunch().catchError((_) => false),
      onCreateAnother: ({required creation, required agentTabId}) async {
        await controller.completePromptWorkspaceCreation(
          creation: creation,
          agentTabId: agentTabId,
        );
        if (context.mounted) {
          _showWorkspaceCreationToast(context, creation);
        }
      },
    ),
  );
  if (!context.mounted || promptResult == null) {
    return;
  }

  WorkspaceCreationResult? result = promptResult.creation;
  if (promptResult.openManual) {
    result = await _showManualWorkspaceDialog(
      context,
      ref,
      controller: controller,
      projects: projects,
      parentCandidates: parentCandidates,
      sshTargets: sshTargets,
      resolvedInitialProject: resolvedInitialProject,
      retryJobId: boundJobId,
    );
  } else {
    final creation = promptResult.creation;
    if (creation != null) {
      await controller.completePromptWorkspaceCreation(
        creation: creation,
        agentTabId: promptResult.agentTabId,
      );
    }
  }

  if (result != null && context.mounted) {
    _showWorkspaceCreationToast(context, result);
  }
}

Future<WorkspaceCreationResult?> _showManualWorkspaceDialog(
  BuildContext context,
  WidgetRef ref, {
  required WorkbenchController controller,
  required List<Project> projects,
  required List<WorkspaceParentCandidate> parentCandidates,
  required List<SshTarget> sshTargets,
  required Project? resolvedInitialProject,
  ManualWorkspaceCreateRequest? retryManual,
  String? retryError,
  String? retryJobId,
}) {
  var boundJobId = retryJobId;
  return showDialog<WorkspaceCreationResult>(
    context: context,
    builder: (_) => CreateWorkspaceDialog(
      projects: projects,
      initialProject: resolvedInitialProject,
      initialSourceBranch: retryManual?.sourceBranch,
      initialNewBranchName: retryManual?.newBranchName,
      initialName: retryManual?.name,
      initialParentWorkspaceId: retryManual?.parentWorkspaceId,
      initialHostId: retryManual?.hostId,
      initialReuseExistingBranch: retryManual?.reuseExistingBranch ?? false,
      initialCreationError: retryManual == null ? null : retryError,
      enqueueCreate: (request) {
        boundJobId ??= const Uuid().v4();
        final done = ref
            .read(backgroundSetupJobsProvider.notifier)
            .enqueueManualWorkspace(request, jobId: boundJobId);
        if (done == null) {
          return null;
        }
        return done.then((_) {
          boundJobId = const Uuid().v4();
        });
      },
      parentCandidates: parentCandidates,
      sshTargets: sshTargets,
      loadBranches: controller.listSourceBranches,
      getProjectActiveBranch: (project) {
        final state = ref.read(workbenchControllerProvider);
        final workspaces = state.workspacesFor(project.id);
        if (workspaces.isEmpty) return null;
        try {
          final activeWorkspace = workspaces.firstWhere(
            (w) => w.id == state.activeWorkspaceId,
            orElse: () => workspaces.firstWhere(
              (w) => w.isMain,
              orElse: () => workspaces.first,
            ),
          );
          return activeWorkspace.branch;
        } catch (_) {
          return null;
        }
      },
      getProjectWorkspaceBranches: (project) {
        final state = ref.read(workbenchControllerProvider);
        return state
            .workspacesFor(project.id)
            .where((workspace) => workspace.isActive)
            .map((workspace) => workspace.branch?.trim() ?? '')
            .where((branch) => branch.isNotEmpty)
            .toSet();
      },
      checkBranchExists: (project, branchName) async {
        final gitBackend = ref.read(gitBackendProvider);
        return gitBackend.branchExists(project.repoPath, branchName);
      },
      onCreateWorkspace:
          ({
            required project,
            required sourceBranch,
            required newBranchName,
            required reuseExistingBranch,
            name,
            parentWorkspaceId,
            hostId,
          }) async {
            return controller.createWorkspace(
              project: project,
              sourceBranch: sourceBranch,
              newBranchName: newBranchName,
              reuseExistingBranch: reuseExistingBranch,
              name: name,
              parentWorkspaceId: parentWorkspaceId,
              hostId: hostId,
            );
          },
      onAddProject: () {
        Navigator.of(context).pop();
        unawaited(showAddProjectFlow(context, ref));
      },
      onWorkspaceCreated: (creation) {
        if (context.mounted) {
          _showWorkspaceCreationToast(context, creation);
        }
      },
    ),
  );
}

Future<List<SshTarget>> _loadSshTargets(WidgetRef ref) async {
  try {
    return await ref.read(sshTargetRepositoryProvider).list();
  } catch (_) {
    return const <SshTarget>[];
  }
}

void _showWorkspaceCreationToast(
  BuildContext context,
  WorkspaceCreationResult result,
) {
  if (result.hasSetupWarnings) {
    AleraToast.show(
      context,
      message:
          'Workspace created with setup warnings: ${result.setupReport.summary}',
      tone: .error,
      duration: const Duration(seconds: 6),
    );
    return;
  }
  if (result.hasParentLinkError) {
    AleraToast.show(
      context,
      message: 'Workspace created, but parent link failed',
      tone: .error,
      duration: const Duration(seconds: 6),
    );
    return;
  }
  AleraToast.show(context, message: 'Workspace created', tone: .success);
}
