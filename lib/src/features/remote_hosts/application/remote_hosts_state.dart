import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

/// One host as every remote host surface shows it: the stored target, its
/// unified status, and what this app knows about work in flight.
class const RemoteHostView({
  required final SshTarget target,
  required final RemoteHostStatus status,
  required final HostOs os,
  required final String address,
  final bool busy = false,
  final RemoteHostInstallProgress? installProgress,
  final HostLinkState? link,

  /// The last action on this host that failed, as a sentence.
  final String? actionError,
}) {
  String get id => target.id;

  String get alias => target.alias;

  /// `macOS arm64`, from what the runtime probed or, before the first
  /// install, what the user entered. Null when neither is known.
  String? get platformLabel {
    final arch = target.runtimeArch ?? target.arch;
    if (os == HostOs.unknown) {
      return arch;
    }
    return arch == null ? os.label : '${os.label} $arch';
  }
}

/// Which remote host features the connected runtime offers.
class const RemoteHostCapabilities({
  final bool hostLinks = false,
  final bool hostStatus = false,
  final bool runtimeUpdate = false,
  final bool identityFile = false,
});

class const RemoteHostsState({
  final List<RemoteHostView> hosts = const <RemoteHostView>[],
  final bool loading = true,
  final String? loadError,
  final Set<String> busyHostIds = const <String>{},
  final Set<String> installDialogHostIds = const <String>{},
  final RemoteHostCapabilities capabilities = const RemoteHostCapabilities(),
}) {
  RemoteHostView? hostById(String? hostId) {
    for (final host in hosts) {
      if (host.id == hostId) {
        return host;
      }
    }
    return null;
  }

  /// Hosts New Workspace may pick.
  List<RemoteHostView> get readyHosts => <RemoteHostView>[
    for (final host in hosts)
      if (host.status.isReady) host,
  ];

  /// The host whose state the status bar chip reports: the most severe one.
  RemoteHostView? get worstHost {
    RemoteHostView? worst;
    for (final host in hosts) {
      if (worst == null || host.status.severity > worst.status.severity) {
        worst = host;
      }
    }
    return worst;
  }

  bool isInstallDialogOpen(String hostId) =>
      installDialogHostIds.contains(hostId);
}
