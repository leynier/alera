part of 'workbench_dialog_launchers.dart';

/// Whether Add Project offers Add Remote Project: the runtime has to serve
/// `project.registerRemote` (`projectHostsV1`). Without a ready host the form
/// itself explains what is missing and offers Add Host.
bool _remoteProjectAvailable(WidgetRef ref) {
  return ref.watch(projectHostsSupportedProvider).value ?? false;
}

/// Opens the form that creates a project living only on an SSH host,
/// starting on [initialHostId] when it is one of the hosts offered.
///
/// Nothing here selects the new project or a workspace: the runtime announces
/// `projectsChanged` and the sidebar lists the project from that. The request
/// is not cancellable, so a dialog closed mid-clone still gets its outcome as
/// a toast.
Future<void> showAddRemoteProjectFlow(
  BuildContext context,
  WidgetRef ref, {
  String? initialHostId,
}) async {
  final client = ref.read(projectHostsClientProvider);
  var dialogOpen = true;
  var addHost = false;
  final project = await showDialog<Project>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final remoteHosts = ref.watch(remoteHostsControllerProvider);
        return AddRemoteProjectDialog(
          initialHostId: initialHostId,
          hosts: remoteHosts.hosts,
          hostsLoading: remoteHosts.loading,
          onAddHost: () {
            addHost = true;
            Navigator.of(dialogContext).pop();
          },
          registerRemoteProject: _remoteProjectRegistrar(
            client,
            isDialogOpen: () => dialogOpen,
          ),
        );
      },
    ),
  );
  dialogOpen = false;
  if (project != null) {
    _publishRemoteProjectAdded(project);
  }
  // Add Host ends with its own "Add a Project to This Host" step, which
  // reopens this form on the new host; keeping this one open would stack two.
  if (addHost && context.mounted) {
    await showAddRemoteHostFlow(context, ref);
  }
}

/// Registers a remote project and, once the dialog that asked is gone,
/// reports the outcome as a toast instead.
RegisterRemoteProject _remoteProjectRegistrar(
  RuntimeProjectHostsClient client, {
  required bool Function() isDialogOpen,
  String Function(Project project)? successMessage,
}) {
  return (request) async {
    try {
      final project = await client.registerRemote(
        hostId: request.hostId,
        path: request.path,
        cloneUrl: request.cloneUrl,
        name: request.name,
        kind: request.kind,
      );
      if (!isDialogOpen()) {
        _publishRemoteProjectAdded(project, message: successMessage);
      }
      return project;
    } catch (error) {
      if (!isDialogOpen()) {
        AleraToast.publish(
          message: userFacingExceptionMessage(error),
          tone: .error,
        );
      }
      rethrow;
    }
  };
}

void _publishRemoteProjectAdded(
  Project project, {
  String Function(Project project)? message,
}) {
  AleraToast.publish(
    message: message?.call(project) ?? '${project.name} added',
    tone: .success,
  );
}
