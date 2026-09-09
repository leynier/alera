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

Future<void> showHandOffWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
}) async {
  if (!workspace.isMain) {
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
  );
  if (request == null || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(workbenchControllerProvider.notifier)
        .handOffWorkspace(
          workspace: workspace,
          branch: request.branch,
          reuseExistingBranch: request.reuseExistingBranch,
          name: request.name,
        );
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Work handed off. Any moved local changes remain backed up in Git Stashes as "alera handoff recovery".',
      tone: .success,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: error.toString(), tone: .error);
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
      title: 'Hand On to Main?',
      message:
          'This brings the branch and uncommitted changes from "${workspace.name}" onto the main worktree, then removes this child workspace. Open tabs and running terminals move with it.',
      confirmLabel: 'Hand On',
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(workbenchControllerProvider.notifier)
        .handOnWorkspace(project: project, workspace: workspace);
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Work handed on to main. Any moved local changes remain backed up in Git Stashes as "alera handoff recovery".',
      tone: .success,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: error.toString(), tone: .error);
  }
}
