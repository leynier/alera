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
  final projects = state.projects;
  final parentCandidates = <WorkspaceParentCandidate>[
    for (final project in state.projects)
      for (final workspace in state.workspacesFor(project.id))
        if (workspace.isActive)
          WorkspaceParentCandidate(project: project, workspace: workspace),
  ];

  final resolvedInitialProject =
      retryManual?.project ?? retryPrompt?.project ?? initialProject;

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
  final hostEnrollment = ProjectHostEnrollmentController(
    _supportsProjectHosts(ref) ? projectHostAdder(ref) : null,
  );
  // Read from the snapshot the sidebar already keeps rather than asking the
  // host again, so opening the form never waits on a runtime connection, and
  // never starts a watch of its own when nothing else is watching.
  final issueRepository = ref.read(linkedIssueRepositoryProvider);
  final linkedIssuesSupported =
      ref.exists(linkedIssueSnapshotProvider) &&
      ref.read(linkedIssuesSupportedProvider);
  if (!context.mounted) {
    hostEnrollment.dispose();
    return;
  }
  try {
    await _showCreateWorkspaceDialogs(
      context,
      ref,
      controller: controller,
      projects: projects,
      parentCandidates: parentCandidates,
      sshTargets: sshTargets,
      hostEnrollment: hostEnrollment,
      resolvedInitialProject: resolvedInitialProject,
      profiles: profiles,
      runtime: runtime,
      fetchIssue: linkedIssuesSupported ? issueRepository.fetch : null,
      retryManual: retryManual,
      retryPrompt: retryPrompt,
      retryError: retryError,
      remainingRetryJobId: remainingRetryJobId,
    );
  } finally {
    hostEnrollment.dispose();
  }
}

Future<void> _showCreateWorkspaceDialogs(
  BuildContext context,
  WidgetRef ref, {
  required WorkbenchController controller,
  required List<Project> projects,
  required List<WorkspaceParentCandidate> parentCandidates,
  required List<SshTarget> sshTargets,
  required ProjectHostEnrollmentController hostEnrollment,
  required Project? resolvedInitialProject,
  required List<AgentProfile> profiles,
  required PromptWorkspaceRuntimeClient runtime,
  required Future<IssueDetails> Function(String url)? fetchIssue,
  ManualWorkspaceCreateRequest? retryManual,
  PromptWorkspaceCreateRequest? retryPrompt,
  String? retryError,
  String? remainingRetryJobId,
}) async {
  var boundJobId = remainingRetryJobId;
  final workbenchState = ref.read(workbenchControllerProvider);
  final hasWorkspaceSections =
      workbenchState.supportsSections && workbenchState.sections.isNotEmpty;
  final promptResult = await showDialog<PromptWorkspaceDialogResult>(
    context: context,
    builder: (_) => PromptWorkspaceDialog(
      projects: projects,
      agentProfiles: profiles,
      sshTargets: sshTargets,
      hostEnrollment: hostEnrollment,
      defaultAgentProfileId:
          retryPrompt?.profileId ??
          ref.read(settingsControllerProvider).agents.defaultAgentProfileId,
      initialProject: resolvedInitialProject,
      initialPrompt: retryPrompt?.prompt,
      loadPreferredSourceBranch: _loadPreferredSourceBranch(ref),
      initialSourceBranch: retryPrompt?.sourceBranch,
      initialParentWorkspaceId: retryPrompt?.parentWorkspaceId,
      initialHostId: retryPrompt?.hostId,
      initialIssueUrl: retryPrompt?.issueUrl,
      fetchIssue: fetchIssue,
      initialError: retryPrompt == null ? null : retryError,
      initialMode: retryManual != null
          ? NewWorkspaceMode.manual
          : NewWorkspaceMode.fromPrompt,
      manualForm: _buildManualWorkspaceForm(
        context,
        ref,
        controller: controller,
        projects: projects,
        parentCandidates: parentCandidates,
        sshTargets: sshTargets,
        hostEnrollment: hostEnrollment,
        resolvedInitialProject: resolvedInitialProject,
        retryManual: retryManual,
        retryError: retryError,
        fetchIssue: fetchIssue,
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
      ),
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
      loadHostBranchCatalog: controller.loadHostBranchCatalog,
      checkBranchExists: _projectBranchCheck(ref, controller),
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
      initialUseProjectCheckout: retryPrompt?.useProjectCheckout ?? true,
      hasWorkspaceSections: hasWorkspaceSections,
      initialAutoAssignSection: retryPrompt?.autoAssignSection ?? true,
      assignSection: (workspaceId, sectionId) =>
          controller.saveWorkspaceSection(workspaceId, sectionId: sectionId),
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
            issueUrl,
          }) {
            return controller.createWorkspaceForPrompt(
              project: project,
              sourceBranch: sourceBranch,
              newBranchName: newBranchName,
              name: name,
              parentWorkspaceId: parentWorkspaceId,
              hostId: hostId,
              issueUrl: issueUrl,
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

  final creation = promptResult.creation;
  if (creation != null) {
    await controller.completePromptWorkspaceCreation(
      creation: creation,
      agentTabId: promptResult.agentTabId,
    );
    if (context.mounted) {
      _showWorkspaceCreationToast(context, creation);
    }
  }
}

Widget _buildManualWorkspaceForm(
  BuildContext context,
  WidgetRef ref, {
  required WorkbenchController controller,
  required List<Project> projects,
  required List<WorkspaceParentCandidate> parentCandidates,
  required List<SshTarget> sshTargets,
  required ProjectHostEnrollmentController hostEnrollment,
  required Project? resolvedInitialProject,
  required Future<void>? Function(ManualWorkspaceCreateRequest request)
  enqueueCreate,
  required Future<IssueDetails> Function(String url)? fetchIssue,
  ManualWorkspaceCreateRequest? retryManual,
  String? retryError,
}) {
  return CreateWorkspaceDialog(
    embedded: true,
    projects: projects,
    initialProject: resolvedInitialProject,
    loadPreferredSourceBranch: _loadPreferredSourceBranch(ref),
    initialSourceBranch: retryManual?.sourceBranch,
    initialNewBranchName: retryManual?.newBranchName,
    initialName: retryManual?.name,
    initialParentWorkspaceId: retryManual?.parentWorkspaceId,
    initialHostId: retryManual?.hostId,
    initialIssueUrl: retryManual?.issueUrl,
    fetchIssue: fetchIssue,
    initialReuseExistingBranch: retryManual?.reuseExistingBranch ?? false,
    initialUseProjectCheckout: retryManual?.useProjectCheckout ?? true,
    initialCreationError: retryManual == null ? null : retryError,
    enqueueCreate: enqueueCreate,
    parentCandidates: parentCandidates,
    sshTargets: sshTargets,
    hostEnrollment: hostEnrollment,
    loadBranches: controller.listSourceBranches,
    loadHostBranchCatalog: controller.loadHostBranchCatalog,
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
    checkBranchExists: _projectBranchCheck(ref, controller),
    onCreateWorkspace:
        ({
          required project,
          required sourceBranch,
          required newBranchName,
          required reuseExistingBranch,
          name,
          parentWorkspaceId,
          hostId,
          issueUrl,
        }) async {
          return controller.createWorkspace(
            project: project,
            sourceBranch: sourceBranch,
            newBranchName: newBranchName,
            reuseExistingBranch: reuseExistingBranch,
            name: name,
            parentWorkspaceId: parentWorkspaceId,
            hostId: hostId,
            issueUrl: issueUrl,
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
  );
}

Future<String?> Function(Project project) _loadPreferredSourceBranch(
  WidgetRef ref,
) {
  return (project) async {
    try {
      final effective = await ref
          .read(projectConfigServiceProvider)
          .resolve(project);
      return effective.config.newWorkspace.preferredSourceBranch;
    } catch (_) {
      return null;
    }
  };
}

/// Whether a branch exists in the project's own repository. The dialogs only
/// fall back to this without a host branch catalog, and a project that lives
/// only on a server is asked there rather than at a local path it lacks.
Future<bool> Function(Project project, String branchName) _projectBranchCheck(
  WidgetRef ref,
  WorkbenchController controller,
) {
  return PromptWorkspaceBranchChecks(
    hostId: null,
    git: ref.read(gitBackendProvider),
    loadHostCatalog: controller.loadHostBranchCatalog,
    workspaces: () => const <Workspace>[],
  ).branchExists;
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
