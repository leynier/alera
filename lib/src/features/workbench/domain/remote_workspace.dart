import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

const String localWorkspaceHostId = 'local';

bool isRemoteWorkspaceHostId(String? hostId) {
  final value = hostId?.trim();
  return value != null && value.isNotEmpty && value != localWorkspaceHostId;
}

String? normalizedRemoteHostId(String? hostId) {
  return isRemoteWorkspaceHostId(hostId) ? hostId!.trim() : null;
}

String remoteHostMissingCapabilityMessage() {
  return 'This Alera runtime cannot create remote workspaces yet. Update the app and sidecar, or create the workspace on This Device.';
}

String remoteWorkspaceFilesMissingCapabilityMessage() {
  return 'This Alera runtime cannot browse files on a remote workspace. Update the app and sidecar, then retry.';
}

String remoteWorkspaceWriteUnsupportedMessage() {
  return 'Saving or changing files on a remote SSH workspace is not supported yet. Edit them on the host or in a terminal.';
}

String sshTargetNotFoundMessage(String hostId) {
  return 'ssh target not found: $hostId. Add it in Settings → Remote Hosts, then install the sidecar.';
}

String hostNotBootstrappedMessage(SshTarget target) {
  return "host '${target.alias}' is not bootstrapped. Open Settings → Remote Hosts and install the Alera runtime sidecar, or run `alera ssh-target bootstrap --id ${target.id}`.";
}

String hostUnreachableMessage(SshTarget target) {
  return "host '${target.alias}' (${target.username}@${target.host}:${target.port}) is unreachable. Check SSH agent or key authentication and network, then retry from Settings → Remote Hosts.";
}

String? remoteWorkspaceHostSelectionError({
  required String? hostId,
  required List<SshTarget> targets,
  required bool supportsRemoteSshWorkspaces,
}) {
  final remoteId = normalizedRemoteHostId(hostId);
  if (remoteId == null) {
    return null;
  }
  if (!supportsRemoteSshWorkspaces) {
    return remoteHostMissingCapabilityMessage();
  }
  SshTarget? target;
  for (final candidate in targets) {
    if (candidate.id == remoteId) {
      target = candidate;
      break;
    }
  }
  if (target == null) {
    return sshTargetNotFoundMessage(remoteId);
  }
  if (target.bootstrapStatus != SshBootstrapStatus.installed) {
    return hostNotBootstrappedMessage(target);
  }
  if (target.lastStatus == 'unreachable') {
    return hostUnreachableMessage(target);
  }
  return null;
}

String sshTargetPickerLabel(SshTarget target) {
  if (target.bootstrapStatus != SshBootstrapStatus.installed) {
    return '${target.alias} (Not Bootstrapped)';
  }
  if (target.lastStatus == 'unreachable') {
    return '${target.alias} (Unreachable)';
  }
  return target.alias;
}

String userFacingExceptionMessage(Object error) {
  final mapped = remoteWorkspaceErrorMessage(error);
  if (mapped != null) {
    return mapped;
  }
  return _stripExceptionPrefix(error.toString());
}

String? remoteWorkspaceErrorMessage(Object error) {
  final message = _stripExceptionPrefix(error.toString());
  final lower = message.toLowerCase();
  if (lower.contains('not bootstrapped') ||
      lower.contains('unreachable') ||
      lower.contains('ssh target not found') ||
      lower.contains('cannot create remote workspaces') ||
      lower.contains('cannot browse files on a remote') ||
      lower.contains('remote ssh workspace') ||
      lower.contains('settings → remote hosts')) {
    return message;
  }
  if (lower.contains('unknown terminal host request') &&
      (lower.contains('workspace.files') || lower.contains('hostid'))) {
    return remoteWorkspaceFilesMissingCapabilityMessage();
  }
  return null;
}

String _stripExceptionPrefix(String raw) {
  var message = raw.trim();
  const prefixes = <String>[
    'Exception: ',
    'Bad state: ',
    'StateError: ',
    'FormatException: ',
  ];
  for (final prefix in prefixes) {
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
  }
  return message;
}
