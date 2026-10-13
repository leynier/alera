import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_comparison_loader.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_git_snapshots.g.dart';

class const WorkspaceGitCatalog({
  required final List<String> branches,
  required final String defaultBranch,
  required final List<String> remoteNames,
});

@riverpod
Future<WorkspaceGitCatalog> workspaceGitCatalog(Ref ref, String path) async {
  final source = workspaceSourceControlControllerProvider(path);
  ref.watch(source.select((value) => value.value?.catalogRevision ?? 0));
  await ref.read(source.future);
  final git = ref.read(gitBackendProvider);
  final branches = await git.listBranches(path);
  final defaultBranch = await git.workspaceDefaultBranch(path);
  final remotes = await git.listRemotes(path);
  return WorkspaceGitCatalog(
    branches: branches,
    defaultBranch: defaultBranch,
    remoteNames: remotes.map((remote) => remote.name).toList(growable: false),
  );
}

@riverpod
WorkspaceComparisonLoader workspaceComparisonLoader(
  Ref ref,
  String path,
  String? baseRef,
) {
  final git = ref.read(gitBackendProvider);
  final loader = WorkspaceComparisonLoader(
    loadSnapshot: () => git.workspaceComparison(path, baseRef: baseRef),
  );
  ref.onDispose(loader.dispose);
  return loader;
}

@riverpod
Future<GitWorkspaceComparison> workspaceGitComparison(
  Ref ref,
  String path,
  String? baseRef,
) async {
  final source = workspaceSourceControlControllerProvider(path);
  final revision = ref.watch(
    source.select((value) => value.value?.comparisonRevision ?? 0),
  );
  final loader = ref.watch(workspaceComparisonLoaderProvider(path, baseRef));
  await ref.read(source.future);
  return loader.load(revision);
}
