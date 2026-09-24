import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/host_routed_git_backend.dart';
import 'package:alera/src/shared/infra/git/remote_checkout_index.dart';
import 'package:alera/src/shared/infra/git/runtime_git_backend.dart';
import 'package:alera/src/shared/infra/git/rust_git_backend.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'git_providers.g.dart';

/// The one [GitBackend] the app reads. Paths inside a remote workspace go to
/// that host's runtime backend, everything else to the local bridge, so a
/// caller never has to know where a checkout lives.
///
/// The workbench state is read lazily on each call rather than watched: this
/// provider is a build-time dependency of the services the controller itself
/// uses, and watching it here would close that loop.
@Riverpod(keepAlive: true)
GitBackend gitBackend(Ref ref) {
  final remoteBackends = <String, RuntimeGitBackend>{};
  final remoteWorkspaceIdFor = ref.read(remoteWorkspacePathResolverProvider);
  return HostRoutedGitBackend(
    local: const RustGitBackend(),
    remoteFor: (path) {
      final workspaceId = remoteWorkspaceIdFor(path);
      if (workspaceId == null) {
        return null;
      }
      return remoteBackends.putIfAbsent(
        workspaceId,
        () => RuntimeGitBackend(
          ref.read(runtimeHostClientProvider),
          workspaceId: workspaceId,
          beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
        ),
      );
    },
  );
}

/// The id of the remote workspace whose checkout contains a path, or null when
/// the path is local. Git and workspace-scoped processes route through the
/// same answer, so a checkout can never be local to one and remote to the
/// other.
typedef RemoteWorkspacePathResolver = String? Function(String path);

/// Reads the workbench state lazily, for the reason given on [gitBackend], and
/// rebuilds the index only when that state object changes.
@Riverpod(keepAlive: true)
RemoteWorkspacePathResolver remoteWorkspacePathResolver(Ref ref) {
  WorkbenchState? indexedState;
  var index = const RemoteCheckoutIndex.empty();
  return (path) {
    final state = ref.read(workbenchControllerProvider);
    if (!identical(state, indexedState)) {
      indexedState = state;
      index = remoteCheckoutIndexFor(state);
    }
    return index.remoteWorkspaceIdFor(path);
  };
}

/// Remote checkouts come from remote workspaces; local roots are every local
/// workspace path plus every project checkout, which is where worktree and
/// branch operations on the main repository land. A project that lives only on
/// a host has no folder here: listing its `repoPath` as local would send the
/// git calls of a workspace opened on that very folder to the local bridge.
RemoteCheckoutIndex remoteCheckoutIndexFor(WorkbenchState state) {
  final remote = <RemoteCheckoutEntry>[];
  final local = <String>[
    for (final project in state.projects)
      if (!project.isRemoteOnly) project.repoPath,
  ];
  for (final workspaces in state.workspacesByProject.values) {
    for (final workspace in workspaces) {
      if (workspace.isRemote) {
        remote.add(
          RemoteCheckoutEntry(workspaceId: workspace.id, path: workspace.path),
        );
      } else {
        local.add(workspace.path);
      }
    }
  }
  if (remote.isEmpty) {
    return const RemoteCheckoutIndex.empty();
  }
  return RemoteCheckoutIndex(remote, local);
}
