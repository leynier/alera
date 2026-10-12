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
      builder: (dialogContext, ref, _) => ProjectHostsDialog(
        project: project,
        hosts: ref.watch(remoteHostsControllerProvider).hosts,
        loadHosts: () => client.list(project.id),
        addProjectToHost: addProjectToHost,
        removeFromHost: (hostId) =>
            client.remove(projectId: project.id, hostId: hostId),
        onOpenHost: (hostId) =>
            unawaited(openRemoteHostSettings(dialogContext, hostId: hostId)),
        onManageHosts: () => unawaited(openRemoteHostSettings(dialogContext)),
        onAddHost: () => unawaited(showAddRemoteHostFlow(dialogContext, ref)),
      ),
    ),
  );
}

/// Opens Add Project to Host for [hostId]: an existing Git project, or a new
/// project that lives only there, starting on [mode]. A request that outlives
/// the dialog still reports its outcome as a toast.
Future<void> showAddProjectToHostFlow(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  AddProjectToHostMode mode = .existingProject,
}) async {
  final client = ref.read(projectHostsClientProvider);
  final addProjectToHost = projectHostAdder(ref);
  String hostLabel() =>
      ref.read(remoteHostsControllerProvider).hostById(hostId)?.alias ?? hostId;
  String addedMessage(Project project) =>
      '${project.name} added to ${hostLabel()}';
  var dialogOpen = true;
  final project = await showDialog<Project>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) => AddProjectToHostDialog(
        hostId: hostId,
        initialMode: mode,
        hosts: ref.watch(remoteHostsControllerProvider).hosts,
        projects: ref.watch(projectListProvider).value ?? const <Project>[],
        addProjectToHost: (project, hostId, existingPath) async {
          try {
            final added = await addProjectToHost(project, hostId, existingPath);
            if (!dialogOpen) {
              AleraToast.publish(message: addedMessage(added), tone: .success);
            }
            return added;
          } catch (error) {
            if (!dialogOpen) {
              AleraToast.publish(
                message: userFacingExceptionMessage(error),
                tone: .error,
              );
            }
            rethrow;
          }
        },
        registerRemoteProject: _remoteProjectRegistrar(
          client,
          isDialogOpen: () => dialogOpen,
          successMessage: addedMessage,
        ),
      ),
    ),
  );
  dialogOpen = false;
  if (project != null) {
    AleraToast.publish(message: addedMessage(project), tone: .success);
  }
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
