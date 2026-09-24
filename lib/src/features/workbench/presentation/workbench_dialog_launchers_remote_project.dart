part of 'workbench_dialog_launchers.dart';

/// Whether Add Project offers Add Remote Project: the runtime has to serve
/// `project.registerRemote` (`projectHostsV1`) and at least one SSH host has to
/// be bootstrapped. The targets are only watched once the runtime qualifies.
bool _remoteProjectAvailable(WidgetRef ref) {
  if (!(ref.watch(projectHostsSupportedProvider).value ?? false)) {
    return false;
  }
  final targets = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
  return remoteProjectHosts(targets).isNotEmpty;
}

/// Opens the form that creates a project living only on an SSH host.
///
/// Nothing here selects the new project or a workspace: the runtime announces
/// `projectsChanged` and the sidebar lists the project from that. The request
/// is not cancellable, so a dialog closed mid-clone still gets its outcome as
/// a toast.
Future<void> showAddRemoteProjectFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final client = ref.read(projectHostsClientProvider);
  var dialogOpen = true;
  final project = await showDialog<Project>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) => AddRemoteProjectDialog(
        sshTargets: ref.watch(sshTargetsProvider).value ?? const <SshTarget>[],
        registerRemoteProject: (request) async {
          try {
            final project = await client.registerRemote(
              hostId: request.hostId,
              path: request.path,
              cloneUrl: request.cloneUrl,
              name: request.name,
              kind: request.kind,
            );
            if (!dialogOpen) {
              _publishRemoteProjectAdded(project);
            }
            return project;
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
      ),
    ),
  );
  dialogOpen = false;
  if (project != null) {
    _publishRemoteProjectAdded(project);
  }
}

void _publishRemoteProjectAdded(Project project) {
  AleraToast.publish(message: '${project.name} added', tone: .success);
}
