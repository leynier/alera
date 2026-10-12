import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';

enum RemoteHostToastTone { success, warning, error }

/// A toast the workbench should show about one host's link.
class const RemoteHostLinkToast({
  required final String hostId,
  required final String message,
  required final RemoteHostToastTone tone,

  /// Drops stay up longer and offer Open Host; a reconnect is a short note.
  final bool long = false,
  final String? actionLabel,
});

/// One host as the policy sees it.
class const RemoteHostLinkSnapshot({
  required final String hostId,
  required final String alias,
  required final RemoteHostStatus status,
}) {
  factory fromView(RemoteHostView view) => RemoteHostLinkSnapshot(
    hostId: view.id,
    alias: view.alias,
    status: view.status,
  );
}

const String remoteHostOpenHostActionLabel = 'Open Host';

/// Decides which link changes deserve a toast, without touching the UI.
///
/// A connected host that goes offline, starts retrying or fails gets one
/// toast, and a later reconnect gets one "reconnected" note, but only when
/// the drop was announced. Nothing is said for the first snapshot, for the
/// user's own Disconnect (it lands on Not Connected), for install and update
/// transitions, or for the host the Remote Hosts pane is showing, where the
/// state is already on screen.
class RemoteHostLinkToastPolicy {
  Map<String, RemoteHostStatus>? _previous;
  final Set<String> _announced = <String>{};

  List<RemoteHostLinkToast> evaluate(
    Iterable<RemoteHostLinkSnapshot> hosts, {
    String? visibleHostId,
  }) {
    final current = <String, RemoteHostStatus>{
      for (final host in hosts) host.hostId: host.status,
    };
    final previous = _previous;
    _previous = current;
    _announced.removeWhere((hostId) => !current.containsKey(hostId));
    if (previous == null) {
      return const <RemoteHostLinkToast>[];
    }
    final toasts = <RemoteHostLinkToast>[];
    for (final host in hosts) {
      final before = previous[host.hostId];
      if (before == null) {
        continue;
      }
      final visible = host.hostId == visibleHostId;
      final status = host.status;
      if (before is RemoteHostConnected && _isDrop(status)) {
        if (!visible && _announced.add(host.hostId)) {
          toasts.add(_dropToast(host));
        }
        continue;
      }
      if (status is RemoteHostConnected) {
        if (_announced.remove(host.hostId) && !visible) {
          toasts.add(
            RemoteHostLinkToast(
              hostId: host.hostId,
              message: '${host.alias} reconnected',
              tone: RemoteHostToastTone.success,
            ),
          );
        }
        continue;
      }
      if (!_isDrop(status)) {
        // Not Connected, Needs Setup or Installing: the user or an install
        // moved the host on, so a later connect is not a recovery.
        _announced.remove(host.hostId);
      }
    }
    return toasts;
  }

  bool _isDrop(RemoteHostStatus status) {
    return switch (status) {
      RemoteHostOffline() => true,
      RemoteHostError(:final origin) => origin == RemoteHostErrorOrigin.connect,
      RemoteHostConnecting(:final retry) => retry != null,
      _ => false,
    };
  }

  RemoteHostLinkToast _dropToast(RemoteHostLinkSnapshot host) {
    final status = host.status;
    if (status is RemoteHostError) {
      return RemoteHostLinkToast(
        hostId: host.hostId,
        message: '${host.alias}: ${status.detail}',
        tone: RemoteHostToastTone.error,
        long: true,
        actionLabel: remoteHostOpenHostActionLabel,
      );
    }
    final retrying = switch (status) {
      RemoteHostOffline(:final retry) => retry != null,
      RemoteHostConnecting(:final retry) => retry != null,
      _ => false,
    };
    return RemoteHostLinkToast(
      hostId: host.hostId,
      message: retrying
          ? '${host.alias} disconnected. Reconnecting…'
          : '${host.alias} disconnected.',
      tone: RemoteHostToastTone.warning,
      long: true,
      actionLabel: remoteHostOpenHostActionLabel,
    );
  }
}
