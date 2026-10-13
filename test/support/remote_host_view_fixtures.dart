import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

/// A host as the Remote Hosts controller would present it, for widgets that
/// take hosts as plain data.
RemoteHostView remoteHostView(
  String id,
  String alias, {
  RemoteHostStatus status = const RemoteHostDisconnected(),
  HostOs os = HostOs.linux,
  bool busy = false,
  RemoteHostInstallProgress? installProgress,
}) {
  final now = DateTime.utc(2026, 10);
  return RemoteHostView(
    target: SshTarget(
      id: id,
      alias: alias,
      host: '$id.example.test',
      port: 22,
      username: 'leynier',
      authKind: SshAuthKind.agent,
      createdAt: now,
      updatedAt: now,
      bootstrapStatus: status is RemoteHostNeedsSetup
          ? SshBootstrapStatus.notInstalled
          : SshBootstrapStatus.installed,
    ),
    status: status,
    os: os,
    address: 'leynier@$id.example.test',
    busy: busy,
    installProgress: installProgress,
  );
}
