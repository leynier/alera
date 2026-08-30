part of 'mobile_runtime_client.dart';

const Duration _defaultRequestTimeout = Duration(seconds: 20);
const Duration _defaultTransportCloseTimeout = Duration(seconds: 2);

extension MobileRuntimeClientLifecycle on MobileRuntimeClient {
  void _handleSocketClosed() {
    _handleSocketError(switch (_channel.closeCode) {
      4001 => const RuntimeConnectionReplaced(),
      1007 || 1008 || 1009 || 4004 => const RelayCryptoException(
        'Relay authorization or protocol was rejected.',
      ),
      _ => const RuntimeConnectionLost(),
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopRelayRenewal();
    _relayFragmentTimer?.cancel();
    _relayFragments.clear();
    _relaySession?.close();
    final handshake = _relayHandshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(const RuntimeConnectionLost());
    }
    CrashReporting.clearRuntimeContext(this);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Mobile runtime client closed.'));
      }
    }
    _pending.clear();
    final transportClose = () async {
      await _subscription.cancel();
      await _channel.sink.close();
    }();
    // A paused consumer delays a StreamController close future indefinitely.
    // Transport teardown must still complete so the host can reconnect.
    unawaited(_events.close());
    unawaited(_terminalOutput.close());
    unawaited(_connectionFailures.close());
    try {
      await transportClose.timeout(_transportCloseTimeout);
    } on Object catch (error, stackTrace) {
      Logger(
        'MobileRuntimeClient',
      ).warning('runtime transport did not close cleanly', error, stackTrace);
    }
  }
}
