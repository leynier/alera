import 'package:alera/src/features/remote_hosts/domain/remote_host_check_result.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_in_use_exception.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';

/// Outcome of a Remote Hosts action. A failure carries the sentence to show
/// and, for typed conflicts the UI answers differently (a busy host asks to
/// force), the original [cause].
class const RemoteHostActionResult({
  final String? errorMessage,
  final Object? cause,
  final SshTarget? target,
  final RemoteHostCheckResult? check,
  final String? value,
}) {
  factory failure(Object error) => RemoteHostActionResult(
    errorMessage: remoteHostErrorMessage(error),
    cause: error,
  );

  bool get succeeded => errorMessage == null;

  HostBusyException? get hostBusy =>
      cause is HostBusyException ? cause as HostBusyException : null;

  SshTargetInUseException? get inUse => cause is SshTargetInUseException
      ? cause as SshTargetInUseException
      : null;
}

const String remoteHostPasswordUnsupportedMessage =
    'Password login is not supported. Use your SSH agent or a key file.';

const String remoteHostInstallLockedMessage =
    'Finish the install before changing these settings.';

const String remoteHostRuntimeUpdateUnsupportedMessage =
    'This Alera runtime cannot update hosts yet. Update the app on This Device, then retry.';

final RegExp _duplicateAlias = RegExp(
  r'ssh target alias already exists:\s*(.+)$',
  caseSensitive: false,
);

/// The sentence the UI shows for [error], mapping the runtime's raw remote
/// host errors to copy a person can act on.
String remoteHostErrorMessage(Object error) {
  if (error is SshTargetInUseException || error is HostBusyException) {
    return error.toString();
  }
  final raw = error.toString();
  final duplicate = _duplicateAlias.firstMatch(raw.trim());
  if (duplicate != null) {
    return duplicateRemoteHostAliasMessage(duplicate.group(1)!.trim());
  }
  if (raw.toLowerCase().contains('password ssh targets are not supported')) {
    return remoteHostPasswordUnsupportedMessage;
  }
  return userFacingExceptionMessage(error);
}
