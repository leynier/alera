import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The runtime socket ended without the app asking it to, so every stream and
/// pending request on that client is dead. Raised into the provider so screens
/// stop showing a live-looking connection and offer their Retry instead.
class RuntimeConnectionLost implements Exception {
  const RuntimeConnectionLost();

  @override
  String toString() => 'Lost the connection to the host';
}

/// Recoverable transport failure while talking to a paired runtime host.
///
/// VPN down, host asleep, wrong network, or a closed socket are connection
/// state, not application crashes. Screens already render [AsyncError] with
/// Retry; this type just gives them a stable, short message.
class HostUnreachableException implements Exception {
  const HostUnreachableException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'Could not reach the host';
}

/// True only after a host transport error has crossed the runtime boundary and
/// been classified as recoverable connection state.
bool isHostReachabilityFailure(Object error) {
  return error is HostUnreachableException || error is RuntimeConnectionLost;
}

/// Maps an unavailable runtime transport to [HostUnreachableException].
///
/// Call this only at the WebSocket boundary. Authentication, TLS, protocol,
/// and programming errors retain their original types so they stay visible.
Object normalizeHostConnectionError(Object error) {
  if (isHostReachabilityFailure(error)) {
    return error;
  }
  if (_isTransportReachabilityFailure(error)) {
    return HostUnreachableException(error);
  }
  return error;
}

bool _isTransportReachabilityFailure(Object error) {
  if (error is TimeoutException || error is SocketException) {
    return true;
  }
  if (error is HandshakeException ||
      error is TlsException ||
      error is CertificateException) {
    return false;
  }
  if (error is! WebSocketChannelException) {
    return false;
  }
  final inner = error.inner;
  if (inner != null) {
    return _isTransportReachabilityFailure(inner);
  }
  return _looksLikeReachabilityMessage(error.toString().toLowerCase());
}

bool _looksLikeReachabilityMessage(String text) {
  const markers = <String>[
    'no route to host',
    'network is unreachable',
    'network unreachable',
    'connection refused',
    'connection timed out',
    'connection time out',
    'connection reset',
    'connection abort',
    'software caused connection abort',
    'broken pipe',
    'host is down',
    'failed host lookup',
    'name or service not known',
    'nodename nor servname',
    'temporary failure in name resolution',
    'errno = 101',
    'errno = 104',
    'errno = 110',
    'errno = 111',
    'errno = 112',
    'errno = 113',
    'os error: 101',
    'os error: 104',
    'os error: 110',
    'os error: 111',
    'os error: 112',
    'os error: 113',
  ];
  for (final marker in markers) {
    if (text.contains(marker)) {
      return true;
    }
  }
  return false;
}
