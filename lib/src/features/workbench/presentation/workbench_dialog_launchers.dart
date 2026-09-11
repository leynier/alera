import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/automations/presentation/automations_dialog.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:alera/src/features/workbench/presentation/quick_open_dialog.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Shared dialog flows for project/workspace creation and settings.
///
/// Extracted so both the sidebar controls and the keyboard command dispatcher
/// trigger the exact same behavior (dialogs, background job cards, toasts).

Future<void> openSettingsDialog(
  BuildContext context, {
  String initialSectionId = 'application',
  String? initialProjectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(
      initialSectionId: initialSectionId,
      initialProjectId: initialProjectId,
    ),
  );
}

Future<void> openAutomationsDialog(BuildContext context) {
  return showAutomationsDialog(context);
}

/// Opens Quick Open for the active workspace and restores the prior focus when
/// the modal route closes.
Future<void> showQuickOpenFlow(BuildContext context, WidgetRef ref) async {
  if (ref.read(workbenchControllerProvider).activeWorkspace == null) {
    return;
  }
  final previousFocus = FocusManager.instance.primaryFocus;
  await showDialog<void>(
    context: context,
    builder: (_) => const QuickOpenDialog(),
  );
  if (previousFocus?.canRequestFocus ?? false) {
    previousFocus!.requestFocus();
  }
}

Future<String?> showRenameDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  required String initialValue,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(
      title: title,
      labelText: labelText,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

/// Opens the add-project dialog and runs the chosen local-folder or clone flow.
Future<void> showAddProjectFlow(
  BuildContext context,
  WidgetRef ref, {
  ProjectCloneRequest? retryClone,
  String? retryError,
  String? retryJobId,
}) async {
  final jobs = ref.read(backgroundSetupJobsProvider.notifier);
  jobs.beginForm();
  late final AddProjectResult? result;
  try {
    result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => AddProjectDialog(
        startOnClone: retryClone != null,
        initialGitUrl: retryClone?.gitUrl,
        initialDestinationPath: retryClone?.destinationPath,
        initialName: retryClone?.name,
        initialError: retryError,
      ),
    );
    if (result is CloneProjectResult) {
      unawaited(
        jobs.enqueueProjectClone(
          ProjectCloneRequest(
            gitUrl: result.gitUrl,
            destinationPath: result.destinationPath,
            name: result.name,
          ),
          jobId: retryJobId,
        ),
      );
    }
  } finally {
    jobs.endForm();
  }
  if (result == null) {
    return;
  }
  if (result case AddLocalProjectResult()) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      await controller.addLocalProject(path: result.path, name: result.name);
      AleraToast.publish(message: 'Project added', tone: .success);
    } catch (error) {
      AleraToast.publish(message: error.toString(), tone: .error);
    }
  }
}

class const _RenameDialog({
  required final String title,
  required final String labelText,
  required final String initialValue,
  required final String confirmLabel,
}) extends StatefulWidget {
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialValue.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = '${widget.labelText} is required');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              labelText: widget.labelText,
              errorText: _errorText,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
