import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_submodule_status_provider.g.dart';

@riverpod
Future<GitStatusResult> workspaceSubmoduleStatus(
  Ref ref, {
  required String workspacePath,
  required String submodulePath,
  required GitChangeArea area,
}) async {
  ref.watch(workspaceSourceControlControllerProvider(workspacePath));
  final result = await ref
      .watch(gitBackendProvider)
      .submoduleStatus(
        path: workspacePath,
        submodulePath: submodulePath,
        area: area,
      );
  final entries = result.entries
      .map((entry) => entry.insideSubmodule(submodulePath))
      .toList(growable: false);
  return GitStatusResult(
    entries: entries,
    groups: GitChangeGroup.fromEntries(entries),
  );
}
