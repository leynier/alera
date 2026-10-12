part of 'workbench_dialog_launchers.dart';

/// Opens Settings on Remote Hosts, on [hostId] when given.
Future<void> openRemoteHostSettings(BuildContext context, {String? hostId}) {
  return openSettingsDialog(
    context,
    initialSectionId: 'remoteHosts',
    initialHostId: hostId,
  );
}

/// Runs Add Host and answers the id of the host it registered, if any. When
/// the user asks to add a project from the last step, the remote project form
/// opens next, on that host.
Future<String?> showAddRemoteHostFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final outcome = await showDialog<AddRemoteHostOutcome>(
    context: context,
    builder: (_) => const AddRemoteHostDialog(),
  );
  if (outcome == null) {
    return null;
  }
  if (outcome.addProject && context.mounted) {
    await showAddRemoteProjectFlow(context, ref, initialHostId: outcome.hostId);
  }
  return outcome.hostId;
}
