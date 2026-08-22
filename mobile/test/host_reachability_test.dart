import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('normalizeHostConnectionError', () {
    test('classifies Android no-route failures as host unreachable', () {
      final socketError = SocketException(
        'No route to host',
        osError: const OSError('No route to host', 113),
        address: InternetAddress('100.110.226.69'),
        port: 42530,
      );
      final channelError = WebSocketChannelException.from(socketError);

      final normalized = normalizeHostConnectionError(channelError);

      expect(normalized, isA<HostUnreachableException>());
      expect(
        (normalized as HostUnreachableException).cause,
        same(channelError),
      );
      expect(isHostReachabilityFailure(normalized), isTrue);
    });

    test('classifies connection timeouts as host unreachable', () {
      final timeout = TimeoutException('Connection timed out.');

      final normalized = normalizeHostConnectionError(timeout);

      expect(normalized, isA<HostUnreachableException>());
    });

    test('classifies message-only transport failures', () {
      final channelError = WebSocketChannelException(
        'SocketException: No route to host (OS Error: No route to host, errno = 113)',
      );

      final normalized = normalizeHostConnectionError(channelError);

      expect(normalized, isA<HostUnreachableException>());
    });

    test('preserves TLS, protocol, and programming failures', () {
      final tlsError = WebSocketChannelException.from(
        const HandshakeException('Certificate verification failed.'),
      );
      final protocolError = WebSocketChannelException(
        'The server returned HTTP status 401.',
      );
      final stateError = StateError('Device token is invalid.');
      final formatError = const FormatException('Malformed host response.');

      expect(normalizeHostConnectionError(tlsError), same(tlsError));
      expect(normalizeHostConnectionError(protocolError), same(protocolError));
      expect(normalizeHostConnectionError(stateError), same(stateError));
      expect(normalizeHostConnectionError(formatError), same(formatError));
      expect(isHostReachabilityFailure(tlsError), isFalse);
    });
  });
}
