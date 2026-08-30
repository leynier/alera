part of 'terminal_host_pty_session.dart';

final class _TerminalHostPtySessionLeases {
  final Map<String, Set<_TerminalHostPtySessionLease>> _active =
      <String, Set<_TerminalHostPtySessionLease>>{};

  _TerminalHostPtySessionLease acquire(String sessionId) {
    final lease = _TerminalHostPtySessionLease._(this, sessionId);
    _active
        .putIfAbsent(sessionId, () => <_TerminalHostPtySessionLease>{})
        .add(lease);
    return lease;
  }

  bool release(_TerminalHostPtySessionLease lease) {
    if (lease._released) {
      return false;
    }
    lease._released = true;
    final leases = _active[lease._sessionId];
    if (leases == null || !leases.remove(lease) || leases.isNotEmpty) {
      return false;
    }
    _active.remove(lease._sessionId);
    return true;
  }

  void terminate(_TerminalHostPtySessionLease lease) {
    if (lease._released) {
      return;
    }
    final leases = _active.remove(lease._sessionId);
    if (leases == null) {
      lease._released = true;
      return;
    }
    for (final activeLease in leases) {
      activeLease._released = true;
    }
  }
}

final class _TerminalHostPtySessionLease._(
  final _TerminalHostPtySessionLeases _owner,
  final String _sessionId,
) {
  bool _released = false;

  bool release() => _owner.release(this);

  void terminate() => _owner.terminate(this);
}
