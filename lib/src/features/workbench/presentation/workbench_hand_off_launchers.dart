import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_hand_off_dialog.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera/src/features/workbench/application/workspace_handoff_context.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:uuid/uuid.dart';

import 'workspace_relocation_retry_flow.dart';

Future<void> showHandOffWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
}) async {
  if (!workspace.isMain) {
    return;
  }
  if (workspace.isRemote) {
    final branch = workspace.branch?.trim();
    if (branch == null || branch.isEmpty || branch == 'HEAD') {
      AleraToast.show(
        context,
        message: 'The remote branch is unavailable. Refresh the workspace branch on its host before Hand Off.',
        tone: .error,
      );
      return;
    }
    final request = await showWorkspaceHandOffDialog(
      context: context,
      currentBranch: branch,
      branchContextNotice:
          'Last recorded remote branch: $branch. The owning host verifies branch availability and shared changes before moving this task. If its branch changed, refresh the workspace and choose again.',
    );
    if (request != null && context.mounted) {
      await _performHandOff(context, ref, workspace, request);
    }
    return;
  }
  String currentBranch;
  String defaultBranch;
  final git = ref.read(gitBackendProvider);
  try {
    currentBranch = await ref
        .read(gitBackendProvider)
        .currentBranch(workspace.path);
    defaultBranch = await git.defaultBranch(workspace.path);
    if (currentBranch == 'HEAD') {
      throw StateError('Check out a branch before handing off');
    }
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  final runtime = PromptWorkspaceRuntimeClient(
    ref.read(runtimeHostClientProvider),
    beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
  );
  String? operationId;
  var generation = 0;
  Future<void> cancelGeneration() async {
    generation++;
    final id = operationId;
    operationId = null;
    if (id != null) await runtime.cancel(id);
  }

  final request = await showWorkspaceHandOffDialog(
    context: context,
    currentBranch: currentBranch,
    defaultBranch: defaultBranch,
    cancelGeneration: cancelGeneration,
    generateBranch: () async {
      final revision = generation;
      final prompt = await workspaceHandoffContext(
        git: git,
        path: workspace.path,
        workspaceName: workspace.name,
        agentTitles: ref
            .read(workbenchControllerProvider)
            .tabsFor(workspace.id)
            .map((tab) => tab.title),
        projectName: ref
            .read(workbenchControllerProvider)
            .projects
            .where((entry) => entry.id == workspace.projectId)
            .firstOrNull
            ?.name,
        agentContext: ref
            .read(workbenchControllerProvider)
            .tabsFor(workspace.id)
            .expand(
              (tab) => [
                if (tab.payload['agentProfileLaunchV1'] case {
                  'profile': {'name': final String name},
                })
                  'Profile: $name',
                if (tab.payload['initialPrompt'] case final String prompt)
                  'Task: $prompt',
              ],
            ),
      );
      if (revision != generation) throw StateError('Generation cancelled');
      final id = const Uuid().v4();
      operationId = id;
      final identity = await runtime.generateIdentity(
        operationId: id,
        projectId: workspace.projectId,
        prompt: prompt,
        tabId: ref
            .read(workbenchControllerProvider)
            .activeTabIdByWorkspace[workspace.id],
      );
      if (revision != generation) throw StateError('Generation cancelled');
      if (operationId == id) operationId = null;
      if (!await git.isValidBranchName(identity.branchName) ||
          await git.branchExists(workspace.path, identity.branchName)) {
        throw StateError('Generated branch is invalid or already exists');
      }
      return identity.branchName;
    },
    validateBranch: (branch) async {
      if (!await git.isValidBranchName(branch)) {
        return 'Enter a valid Git branch name';
      }
      if (branch != currentBranch &&
          await git.branchExists(workspace.path, branch)) {
        return 'Branch already exists';
      }
      return null;
    },
    validateReplacementBranch: (branch) async {
      if (!await git.isValidBranchName(branch) ||
          !await git.branchExists(workspace.path, branch)) {
        return 'Choose an existing replacement branch';
      }
      return null;
    },
  );
  if (request == null || !context.mounted) {
    return;
  }
  await _performHandOff(context, ref, workspace, request);
}

Future<void> _performHandOff(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
  WorkspaceHandOffRequest request,
) async {
  final completed = await runWorkspaceRelocationWithRetry(
    context: context,
    action: 'Hand Off',
    perform: (relocationId) async {
      await ref
          .read(workbenchControllerProvider.notifier)
          .handOffWorkspace(
            relocationId: relocationId,
            workspace: workspace,
            branch: request.branch,
            reuseExistingBranch: request.reuseExistingBranch,
            moveChanges: request.moveChanges,
            replacementBranch: request.replacementBranch,
          );
    },
  );
  if (completed && context.mounted) {
    AleraToast.show(
      context,
      message: 'Workspace moved to its worktree. Any transferred local changes remain backed up in Git Stashes.',
      tone: .success,
    );
  }
}

Future<void> showHandOnWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  required Project project,
  required Workspace workspace,
}) async {
  if (workspace.isMain) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: 'Hand On to Project Folder?',
      message:
          'This moves "${workspace.name}" to the project folder and brings its branch and uncommitted changes with it. All workspaces on that folder share the resulting branch and files. The task and its tabs keep their identity. Stop this task’s processes first; its old worktree is removed after the move succeeds.',
      confirmLabel: 'Hand On',
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final completed = await runWorkspaceRelocationWithRetry(
    context: context,
    action: 'Hand On',
    perform: (relocationId) async {
      await ref
          .read(workbenchControllerProvider.notifier)
          .handOnWorkspace(
            relocationId: relocationId,
            project: project,
            workspace: workspace,
          );
    },
  );
  if (completed && context.mounted) {
    AleraToast.show(
      context,
      message: 'Workspace moved to the project folder. Any transferred local changes remain backed up in Git Stashes.',
      tone: .success,
    );
  }
}
