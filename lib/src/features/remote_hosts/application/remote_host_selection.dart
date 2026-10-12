import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';

RemoteHostView? remoteHostViewById(List<RemoteHostView> hosts, String? hostId) {
  final remoteId = normalizedRemoteHostId(hostId);
  if (remoteId == null) {
    return null;
  }
  for (final host in hosts) {
    if (host.id == remoteId) {
      return host;
    }
  }
  return null;
}

/// The name a form shows for [hostId]: the alias, "This Device" for the local
/// host, or the raw id once the host is no longer registered.
String remoteHostViewLabel(List<RemoteHostView> hosts, String? hostId) {
  final remoteId = normalizedRemoteHostId(hostId);
  if (remoteId == null) {
    return 'This Device';
  }
  return remoteHostViewById(hosts, remoteId)?.alias ?? remoteId;
}

/// Why a workspace cannot be created on [host] right now, or null when it
/// can. An offline host is not a reason: the runtime connects on demand.
String? remoteHostNotReadyMessage(RemoteHostView host) {
  return switch (host.status) {
    RemoteHostNeedsSetup() =>
      'The Alera runtime is not installed on ${host.alias} yet.',
    RemoteHostInstalling() =>
      'The Alera runtime is still installing on ${host.alias}.',
    RemoteHostError(:final detail) => '${host.alias}: $detail',
    _ => null,
  };
}

/// Why New Workspace cannot use [hostId], or null when it can.
String? remoteHostSelectionError({
  required String? hostId,
  required List<RemoteHostView> hosts,
  required bool supportsRemoteSshWorkspaces,
}) {
  final remoteId = normalizedRemoteHostId(hostId);
  if (remoteId == null) {
    return null;
  }
  if (!supportsRemoteSshWorkspaces) {
    return remoteHostMissingCapabilityMessage();
  }
  final host = remoteHostViewById(hosts, remoteId);
  if (host == null) {
    return sshTargetNotFoundMessage(remoteId);
  }
  return remoteHostNotReadyMessage(host);
}
