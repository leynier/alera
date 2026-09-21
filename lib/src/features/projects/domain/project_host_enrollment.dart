import 'package:alera/src/features/projects/domain/project.dart';

/// Whether New Workspace can use a host for a project, and if not, what the
/// user can do about it.
enum ProjectHostEnrollment {
  /// The project has a checkout on the host, or the runtime is too old to say.
  enrolled,

  /// A Git project that can be cloned or registered on the remote host.
  addable,

  /// A folder project stays on the one host it was registered on.
  folderProject,

  /// A remote-only project; the runtime cannot add this device to it.
  thisDevice,
}

/// Classifies [hostId] (`null` or blank means this device) for [project].
///
/// A runtime without `projectHostsV1` reports no checkouts at all, so an
/// absent one proves nothing there and the host is treated as [enrolled]:
/// blocking would break remote workspaces registered through an older path.
ProjectHostEnrollment projectHostEnrollment({
  required Project project,
  required String? hostId,
  required bool supportsProjectHosts,
}) {
  if (!supportsProjectHosts || project.isOnHost(hostId)) {
    return ProjectHostEnrollment.enrolled;
  }
  final host = hostId?.trim();
  if (host == null || host.isEmpty || host == 'local') {
    return ProjectHostEnrollment.thisDevice;
  }
  if (!project.isGitRepository) {
    return ProjectHostEnrollment.folderProject;
  }
  return ProjectHostEnrollment.addable;
}

/// The host New Workspace starts on for [project]: the caller's choice when it
/// made one, otherwise the host of the project's own folder. For an ordinary
/// project that is this device (null); for a project that lives only on a
/// server it is that server, where "This Device" would be a dead end.
String? initialWorkspaceHostId({
  required Project? project,
  required String? requested,
}) {
  if (requested != null && requested.trim().isNotEmpty) {
    return requested;
  }
  if (project == null || !project.isRemoteOnly) {
    return null;
  }
  return project.primaryHostId;
}

/// Why the runtime would refuse to remove a project from a host, or null when
/// the removal is allowed. Mirrors `project.hosts.remove` so the control is
/// disabled up front instead of failing after the click.
String? projectHostRemovalBlockedReason({
  required bool primary,
  required int workspaceCount,
  required int hostCount,
}) {
  if (hostCount <= 1) {
    return "This is the project's only host.";
  }
  if (primary) {
    return "The primary host holds the project's main folder.";
  }
  if (workspaceCount > 0) {
    return 'Remove the workspaces on this host first.';
  }
  return null;
}

/// [project] with a checkout on [checkout]'s host, replacing any previous one.
Project projectWithCheckout(Project project, ProjectCheckout checkout) {
  return project.copyWith(
    checkouts: List<ProjectCheckout>.unmodifiable(<ProjectCheckout>[
      for (final existing in project.checkouts)
        if (existing.hostId != checkout.hostId) existing,
      checkout,
    ]),
  );
}
