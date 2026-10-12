import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_runtime_version.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

enum RemoteHostErrorOrigin { install, connect }

/// Badge tone for a status. Presentation maps it to `AleraBadgeTone`, so the
/// domain stays free of widget imports.
enum RemoteHostStatusTone { neutral, attention, info, success, error }

/// One state per host, as the UI shows it. The runtime reports it as
/// `hostStatus` (`remoteHostStatusV1`); [derive] rebuilds it from the target,
/// its link and install progress on a runtime that does not.
sealed class const RemoteHostStatus() {
  /// The `hostStatus` payload, or null when [json] is absent or names a state
  /// this app does not know, so the caller can fall back to [derive].
  static RemoteHostStatus? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final detail = _text(json['detail']);
    final retry = HostLinkRetry.fromJson(json['retry']);
    return switch (json['state']) {
      'needsSetup' => RemoteHostNeedsSetup(detail: detail),
      'installing' => RemoteHostInstalling(stage: _text(json['stage'])),
      'disconnected' => const RemoteHostDisconnected(),
      'offline' => RemoteHostOffline(detail: detail, retry: retry),
      'connecting' => RemoteHostConnecting(retry: retry),
      'connected' => RemoteHostConnected(
        updateAvailable: json['runtimeUpdateAvailable'] == true,
        satelliteVersion: _text(json['satelliteVersion']),
        hubVersion: _text(json['hubVersion']),
      ),
      'error' => RemoteHostError(
        detail: detail ?? _genericConnectError,
        origin: json['origin'] == 'install'
            ? RemoteHostErrorOrigin.install
            : RemoteHostErrorOrigin.connect,
      ),
      _ => null,
    };
  }

  /// The status a runtime without `remoteHostStatusV1` cannot report, in the
  /// same precedence the runtime uses: a running install, then setup, then
  /// the link. [hasInstallJob] is false once the runtime's job list is known
  /// to hold nothing for this host, which turns an interrupted install back
  /// into Needs Setup; null means the list is not known yet.
  static RemoteHostStatus derive(
    SshTarget target,
    HostLinkState? link,
    SshTargetBootstrapProgress? progress, {
    bool? hasInstallJob,
    String? hubVersion,
  }) {
    final install = progress?.targetId == target.id ? progress : null;
    switch (install?.status) {
      case SshBootstrapStatus.installing:
        return RemoteHostInstalling(stage: install?.stage);
      case SshBootstrapStatus.failed:
        return RemoteHostError(
          detail: install?.error ?? target.lastError ?? _genericInstallError,
          origin: RemoteHostErrorOrigin.install,
        );
      default:
        break;
    }
    final installed =
        target.bootstrapStatus == SshBootstrapStatus.installed ||
        install?.status == SshBootstrapStatus.installed;
    if (!installed) {
      if (target.bootstrapStatus == SshBootstrapStatus.installing &&
          install == null &&
          hasInstallJob != false) {
        return const RemoteHostInstalling();
      }
      return RemoteHostNeedsSetup(
        detail: target.bootstrapStatus == SshBootstrapStatus.failed
            ? target.lastError
            : null,
      );
    }
    final unreachable = target.lastStatus == 'unreachable';
    switch (link?.phase) {
      case HostLinkPhase.attached:
        final satelliteVersion =
            link?.satelliteVersion ??
            link?.attachment?.hostVersion ??
            target.runtimeVersion;
        final hub = hubVersion ?? link?.hubVersion;
        return RemoteHostConnected(
          satelliteVersion: satelliteVersion,
          hubVersion: hub,
          updateAvailable:
              link?.runtimeUpdateAvailable ??
              runtimeVersionRelation(hub, satelliteVersion) ==
                  RuntimeVersionRelation.older,
        );
      case HostLinkPhase.connecting:
        return RemoteHostConnecting(retry: link?.retry);
      case HostLinkPhase.failed:
        final error = link?.error;
        if (unreachable || _looksUnreachable(link)) {
          return RemoteHostOffline(detail: error, retry: link?.retry);
        }
        return RemoteHostError(
          detail: error ?? _genericConnectError,
          origin: RemoteHostErrorOrigin.connect,
        );
      case HostLinkPhase.disconnected || null:
        return unreachable
            ? RemoteHostOffline(retry: link?.retry)
            : const RemoteHostDisconnected();
    }
  }

  String get label;

  RemoteHostStatusTone get tone;

  /// Whether New Workspace may pick this host. An offline host stays
  /// selectable because the runtime connects on demand.
  bool get isReady;

  /// Work is in flight and the state will change without the user acting.
  bool get isBusy => false;

  /// Offline draws a dot beside its neutral badge.
  bool get showsDot => false;

  /// Rank for the status bar chip, which shows the worst host: error, then
  /// offline or needs setup, then installing or connecting, then the rest.
  int get severity;
}

final class const RemoteHostNeedsSetup({final String? detail})
    extends RemoteHostStatus {
  @override
  String get label => 'Needs Setup';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.attention;
  @override
  bool get isReady => false;
  @override
  int get severity => 2;
}

final class const RemoteHostInstalling({final String? stage})
    extends RemoteHostStatus {
  @override
  String get label => 'Installing…';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.info;
  @override
  bool get isReady => false;
  @override
  bool get isBusy => true;
  @override
  int get severity => 1;
}

final class const RemoteHostDisconnected() extends RemoteHostStatus {
  @override
  String get label => 'Not Connected';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.neutral;
  @override
  bool get isReady => true;
  @override
  int get severity => 0;
}

final class const RemoteHostOffline({
  final String? detail,
  final HostLinkRetry? retry,
}) extends RemoteHostStatus {
  @override
  String get label => 'Offline';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.neutral;
  @override
  bool get isReady => true;
  @override
  bool get showsDot => true;
  @override
  int get severity => 2;
}

final class const RemoteHostConnecting({final HostLinkRetry? retry})
    extends RemoteHostStatus {
  @override
  String get label => 'Connecting…';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.neutral;
  @override
  bool get isReady => true;
  @override
  bool get isBusy => true;
  @override
  int get severity => 1;
}

final class const RemoteHostConnected({
  final bool updateAvailable = false,
  final String? satelliteVersion,
  final String? hubVersion,
}) extends RemoteHostStatus {
  @override
  String get label => updateAvailable ? 'Update Available' : 'Connected';
  @override
  RemoteHostStatusTone get tone => updateAvailable
      ? RemoteHostStatusTone.info
      : RemoteHostStatusTone.success;
  @override
  bool get isReady => true;
  @override
  int get severity => 0;
}

final class const RemoteHostError({
  required final String detail,
  final RemoteHostErrorOrigin origin = RemoteHostErrorOrigin.connect,
}) extends RemoteHostStatus {
  @override
  String get label => 'Error';
  @override
  RemoteHostStatusTone get tone => RemoteHostStatusTone.error;
  @override
  bool get isReady => false;
  @override
  int get severity => 3;
}

const String _genericConnectError = 'Alera could not connect to this host.';
const String _genericInstallError = 'The Alera runtime install failed.';

/// Mirrors the runtime's `Unreachable` failure kind for a link that reports
/// none: a network-level ssh failure means the machine is offline, not that
/// the runtime on it is broken.
bool _looksUnreachable(HostLinkState? link) {
  final kind = link?.failureKind;
  if (kind != null) {
    return kind == 'unreachable';
  }
  final error = link?.error?.toLowerCase() ?? '';
  const markers = <String>[
    'could not resolve',
    'connection refused',
    'connection timed out',
    'operation timed out',
    'no route to host',
    'network is unreachable',
    'host is down',
  ];
  return markers.any(error.contains);
}

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
