import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

/// Operating system of [target]. Bootstrap records what the sidecar probed in
/// `runtimePlatform`; the user-entered `platform` is only a hint used before
/// the first bootstrap.
HostOs sshTargetHostOs(SshTarget? target) {
  if (target == null) {
    return HostOs.unknown;
  }
  final probed = HostOs.parse(target.runtimePlatform);
  if (probed != HostOs.unknown) {
    return probed;
  }
  return HostOs.parse(target.platform);
}

/// Tooltip for a remote workspace's host marker: the alias the user gave the
/// host, falling back to the raw id when the target is no longer registered.
String workspaceHostTooltip({required String hostId, SshTarget? target}) {
  if (target == null) {
    return hostId;
  }
  final os = sshTargetHostOs(target);
  return os == HostOs.unknown ? target.alias : '${target.alias} (${os.label})';
}

/// Index of [targets] by id for row lookups.
Map<String, SshTarget> sshTargetsById(Iterable<SshTarget> targets) {
  return <String, SshTarget>{for (final target in targets) target.id: target};
}
