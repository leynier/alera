part of 'workbench_dialog_launchers.dart';

/// Opens the Hosts dialog for a Git project: the hosts it is on, with Add and
/// Remove. Callers hide the entry when the runtime lacks `projectHostsV1`.
Future<void> showProjectHostsFlow(
  BuildContext context,
  WidgetRef ref,
  Project project,
) {
  final client = ref.read(projectHostsClientProvider);
  final addProjectToHost = projectHostAdder(ref);
  return showDialog<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) => ProjectHostsDialog(
        project: project,
        sshTargets: ref.watch(sshTargetsProvider).value ?? const <SshTarget>[],
        loadHosts: () => client.list(project.id),
        addProjectToHost: addProjectToHost,
        removeFromHost: (hostId) =>
            client.remove(projectId: project.id, hostId: hostId),
      ),
    ),
  );
}

/// Adds a project to a host and answers the project as the runtime now lists
/// it. Providers are read up front because a clone can outlive the widget that
/// owns [ref].
AddProjectToHost projectHostAdder(WidgetRef ref) {
  final client = ref.read(projectHostsClientProvider);
  final repository = ref.read(projectRepositoryProvider);
  return (project, hostId, existingPath) async {
    final checkout = await client.add(
      projectId: project.id,
      hostId: hostId,
      path: existingPath,
    );
    try {
      for (final listed in await repository.listAll()) {
        if (listed.id == project.id && listed.isOnHost(hostId)) {
          return listed;
        }
      }
    } catch (_) {
      // The checkout is registered either way; fall back to what `add` said.
    }
    return projectWithCheckout(project, checkout);
  };
}

/// Read from the snapshot the sidebar keeps, for the same reason as linked
/// issues: opening New Workspace never waits on a runtime connection.
bool _supportsProjectHosts(WidgetRef ref) {
  return ref.exists(projectHostsSupportedProvider) &&
      (ref.read(projectHostsSupportedProvider).value ?? false);
}
