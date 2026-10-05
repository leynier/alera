import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/preferred_source_branch.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_project_branches.g.dart';

/// Source branches a project-worktree automation can start from, with the
/// one Create Workspace would preselect.
typedef AutomationProjectBranches = ({List<String> branches, String? initial});

@riverpod
Future<AutomationProjectBranches> automationProjectBranches(
  Ref ref,
  String projectId,
) async {
  final project = ref
      .read(workbenchControllerProvider)
      .projects
      .where((item) => item.id == projectId)
      .firstOrNull;
  if (project == null || !project.isGitRepository || project.isRemoteOnly) {
    return (branches: const <String>[], initial: null);
  }
  final branches = await ref
      .read(workbenchControllerProvider.notifier)
      .listSourceBranches(project);
  String? preferred;
  try {
    final effective = await ref
        .read(projectConfigServiceProvider)
        .resolve(project);
    preferred = effective.config.newWorkspace.preferredSourceBranch;
  } catch (_) {
    preferred = null;
  }
  return (
    branches: branches,
    initial: pickDefaultSourceBranch(branches, preferred: preferred),
  );
}
