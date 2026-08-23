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
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
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

/// Shared dialog flows for project/workspace creation and settings.
///
/// Extracted so both the sidebar controls and the keyboard command dispatcher
/// trigger the exact same behavior (dialogs, clone progress, toasts).

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
Future<void> showAddProjectFlow(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<AddProjectResult>(
    context: context,
    builder: (_) => const AddProjectDialog(),
  );
  if (result == null || !context.mounted) {
    return;
  }
  final controller = ref.read(workbenchControllerProvider.notifier);
  try {
    switch (result) {
      case AddLocalProjectResult():
        await controller.addLocalProject(path: result.path, name: result.name);
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project added',
          tone: AleraToastTone.success,
        );
      case CloneProjectResult():
        await _runWithProgress(
          context,
          message: 'Cloning repository…',
          action: () => controller.cloneProject(
            gitUrl: result.gitUrl,
            destinationPath: result.destinationPath,
            name: result.name,
          ),
        );
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project cloned',
          tone: AleraToastTone.success,
        );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: error.toString(),
      tone: AleraToastTone.error,
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String labelText;
  final String initialValue;
  final String confirmLabel;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              mainAxisAlignment: MainAxisAlignment.end,
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
      initialProject?.supportsLinkedWorkspaces == true ? initialProject : null;

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
  if (!context.mounted) {
    return;
  }
  final promptResult = await showDialog<PromptWorkspaceDialogResult>(
    context: context,
    builder: (_) => PromptWorkspaceDialog(
      projects: projects,
      agentProfiles: profiles,
      defaultAgentProfileId: ref
          .read(settingsControllerProvider)
          .agents
          .defaultAgentProfileId,
      initialProject: resolvedInitialProject,
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
          }) {
            return controller.createWorkspaceForPrompt(
              project: project,
              sourceBranch: sourceBranch,
              newBranchName: newBranchName,
              name: name,
              parentWorkspaceId: parentWorkspaceId,
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
    result = await showDialog<WorkspaceCreationResult>(
      context: context,
      builder: (_) => CreateWorkspaceDialog(
        projects: projects,
        initialProject: resolvedInitialProject,
        parentCandidates: parentCandidates,
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
            }) async {
              return controller.createWorkspace(
                project: project,
                sourceBranch: sourceBranch,
                newBranchName: newBranchName,
                reuseExistingBranch: reuseExistingBranch,
                name: name,
                parentWorkspaceId: parentWorkspaceId,
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

void _showWorkspaceCreationToast(
  BuildContext context,
  WorkspaceCreationResult result,
) {
  if (result.hasSetupWarnings) {
    AleraToast.show(
      context,
      message:
          'Workspace created with setup warnings: ${result.setupReport.summary}',
      tone: AleraToastTone.error,
      duration: const Duration(seconds: 6),
    );
    return;
  }
  if (result.hasParentLinkError) {
    AleraToast.show(
      context,
      message: 'Workspace created, but parent link failed',
      tone: AleraToastTone.error,
      duration: const Duration(seconds: 6),
    );
    return;
  }
  AleraToast.show(
    context,
    message: 'Workspace created',
    tone: AleraToastTone.success,
  );
}

Future<T> _runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
}) async {
  var progressOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProjectProgressDialog(message: message),
    ).whenComplete(() => progressOpen = false),
  );
  await Future<void>.delayed(Duration.zero);
  try {
    return await action();
  } finally {
    if (context.mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
