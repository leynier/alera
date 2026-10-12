import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

/// What `sshTarget.check` found, from the `lastStatus` it persisted.
enum RemoteHostReachability {
  unreachable,
  reachable,
  runtimeReady,
  unknown;

  static RemoteHostReachability parse(String? value) {
    return switch (value) {
      'unreachable' => RemoteHostReachability.unreachable,
      'reachable' => RemoteHostReachability.reachable,
      'runtimeReady' => RemoteHostReachability.runtimeReady,
      _ => RemoteHostReachability.unknown,
    };
  }
}

/// One host as `sshTarget.check` answered it: the refreshed target, whose
/// `lastStatus` and `lastCheckedAt` the runtime just wrote.
class const RemoteHostCheckResult({required final SshTarget target}) {
  RemoteHostReachability get reachability =>
      RemoteHostReachability.parse(target.lastStatus);

  bool get reachable =>
      reachability == RemoteHostReachability.reachable ||
      reachability == RemoteHostReachability.runtimeReady;

  /// The probe found a working Alera runtime in the install directory.
  bool get runtimeInstalled =>
      reachability == RemoteHostReachability.runtimeReady;

  DateTime? get checkedAt => target.lastCheckedAt;

  /// The runtime's unified status for the host, when it reports one.
  RemoteHostStatus? get status => target.hostStatus;
}
