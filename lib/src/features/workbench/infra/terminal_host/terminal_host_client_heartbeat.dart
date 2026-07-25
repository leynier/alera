part of 'terminal_host_client.dart';

/// How long to wait between liveness probes once a request has timed out.
const Duration _terminalHostHeartbeatInterval = Duration(seconds: 15);

/// Probe timeout. Short because `status.get` only checks auth and touches no
/// storage, so a healthy host answers it immediately even while busy.
const Duration _terminalHostHeartbeatTimeout = Duration(seconds: 5);

/// Consecutive probe failures before the connection is considered dead. More
/// than one so a single unlucky probe during a burst does not drop every PTY.
const int _terminalHostHeartbeatFailureLimit = 3;

/// Liveness probing for a connection whose requests started timing out.
///
/// Request timeouts no longer tear down the connection, because terminal and
/// runtime traffic share it and a saturated host is not a dead one. Socket
/// events still cover a peer that exits or drops. What is left is a host that
/// is alive but wedged, and that is what these probes detect.
mixin _TerminalHostClientHeartbeat {
  /// Overridable so tests can drive the probe cadence without real waits.
  Duration get _heartbeatInterval;

  Timer? _heartbeatTimer;
  _TerminalHostConnection? _heartbeatConnection;
  int _heartbeatFailures = 0;

  void _noteRequestTimedOut(_TerminalHostConnection connection) {
    if (connection.isClosed || identical(_heartbeatConnection, connection)) {
      return;
    }
    _stopHeartbeat();
    _heartbeatConnection = connection;
    _heartbeatFailures = 0;
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_sendHeartbeat(connection)),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatConnection = null;
    _heartbeatFailures = 0;
  }

  void _stopHeartbeatFor(_TerminalHostConnection connection) {
    if (identical(_heartbeatConnection, connection)) {
      _stopHeartbeat();
    }
  }

  Future<void> _sendHeartbeat(_TerminalHostConnection connection) async {
    if (!identical(_heartbeatConnection, connection) || connection.isClosed) {
      _stopHeartbeatFor(connection);
      return;
    }
    try {
      await _sendHeartbeatRequest(connection);
      // The host answered, so it was only slow. Stop probing until the next
      // timeout suggests otherwise.
      _stopHeartbeatFor(connection);
    } on Object {
      if (!identical(_heartbeatConnection, connection)) {
        return;
      }
      _heartbeatFailures += 1;
      if (_heartbeatFailures >= _terminalHostHeartbeatFailureLimit) {
        _stopHeartbeat();
        _handleConnectionClosed(
          connection,
          StateError('Terminal host stopped answering liveness probes.'),
        );
      }
    }
  }

  Future<void> _sendHeartbeatRequest(_TerminalHostConnection connection);

  void _handleConnectionClosed(
    _TerminalHostConnection connection, [
    Object? error,
  ]);
}
