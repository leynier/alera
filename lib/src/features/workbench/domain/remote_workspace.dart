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
  return 'This Alera runtime cannot create remote workspaces yet. Update Alera, or create the workspace on This Device.';
}

String remoteWorkspaceFilesMissingCapabilityMessage() {
  return 'This Alera runtime cannot browse files on a remote workspace. Update Alera, then retry.';
}

String sshTargetNotFoundMessage(String hostId) {
  return 'This host is no longer registered ($hostId). Pick another host, or add it again from Remote Hosts.';
}

/// The name the UI shows for [hostId]: the target's alias, the raw id when the
/// target is no longer registered, and "This Device" for the local host.
String workspaceHostLabel(List<SshTarget> targets, String? hostId) {
  final remoteId = normalizedRemoteHostId(hostId);
  if (remoteId == null) {
    return 'This Device';
  }
  for (final target in targets) {
    if (target.id == remoteId) {
      return target.alias;
    }
  }
  return remoteId;
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
      // Errors the Alera runtime emits still point at this section by name.
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
