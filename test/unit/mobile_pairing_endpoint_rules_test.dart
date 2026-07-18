import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_endpoint_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isWildcardBindHost', () {
    test('detects wildcard hosts', () {
      expect(isWildcardBindHost('0.0.0.0'), isTrue);
      expect(isWildcardBindHost('::'), isTrue);
      expect(isWildcardBindHost('[::]'), isTrue);
      expect(isWildcardBindHost('127.0.0.1'), isFalse);
      expect(isWildcardBindHost('192.168.1.10'), isFalse);
    });
  });

  group('isLoopbackEndpointHost', () {
    test('accepts localhost and loopback literals', () {
      expect(isLoopbackEndpointHost('localhost'), isTrue);
      expect(isLoopbackEndpointHost('LOCALHOST.'), isTrue);
      expect(isLoopbackEndpointHost('127.0.0.1'), isTrue);
      expect(isLoopbackEndpointHost('127.8.8.8'), isTrue);
      expect(isLoopbackEndpointHost('[::1]'), isTrue);
      expect(isLoopbackEndpointHost('::1'), isTrue);
    });

    test('rejects non-loopback hosts', () {
      expect(isLoopbackEndpointHost('192.168.1.50'), isFalse);
      expect(isLoopbackEndpointHost('alera.example.test'), isFalse);
      expect(isLoopbackEndpointHost('[2001:db8::1]'), isFalse);
    });
  });

  group('parseMobilePairingEndpoint', () {
    test('parses explicit authority ports', () {
      final parts = parseMobilePairingEndpoint('wss://alera.example.test:443');
      expect(parts, isNotNull);
      expect(parts!.scheme, 'wss');
      expect(parts.host, 'alera.example.test');
      expect(parts.port, 443);
    });

    test('parses bracketed IPv6 hosts', () {
      final parts = parseMobilePairingEndpoint('ws://[::1]:6768');
      expect(parts, isNotNull);
      expect(parts!.host, '[::1]');
      expect(parts.port, 6768);
    });

    test('accepts a query after the explicit port', () {
      final parts = parseMobilePairingEndpoint(
        'wss://alera.example.test:443?token=abc',
      );
      expect(parts, isNotNull);
      expect(parts!.port, 443);
    });

    test('rejects a query that only looks like a port', () {
      expect(
        parseMobilePairingEndpoint('wss://alera.example.test?token=:443'),
        isNull,
      );
    });

    test('rejects missing ports and non-websocket schemes', () {
      expect(parseMobilePairingEndpoint('wss://alera.example.test'), isNull);
      expect(parseMobilePairingEndpoint('https://alera.example.test:443'), isNull);
      expect(parseMobilePairingEndpoint('not a url'), isNull);
    });
  });

  group('validateMobilePairingEndpoint', () {
    test('accepts loopback ws endpoints', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'ws://127.0.0.1:6768',
          gatewayEnabled: false,
          gatewayPort: 6768,
        ),
        isNull,
      );
    });

    test('rejects plaintext endpoints outside loopback', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'ws://192.168.1.50:6768',
          gatewayEnabled: false,
          gatewayPort: 6768,
        ),
        contains('wss://'),
      );
    });

    test('accepts wss endpoints outside loopback', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'wss://alera.example.test:443',
          gatewayEnabled: true,
          gatewayPort: 6768,
        ),
        isNull,
      );
    });

    test('rejects zero ports', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'ws://127.0.0.1:0',
          gatewayEnabled: false,
          gatewayPort: 6768,
        ),
        contains('Between 1 And 65535'),
      );
    });

    test('rejects ws port mismatch against an enabled gateway', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'ws://127.0.0.1:7123',
          gatewayEnabled: true,
          gatewayPort: 6123,
        ),
        contains('Match The Enabled Gateway Port 6123'),
      );
    });

    test('allows ws port adoption when the gateway is disabled', () {
      expect(
        validateMobilePairingEndpoint(
          endpoint: 'ws://127.0.0.1:7123',
          gatewayEnabled: false,
          gatewayPort: 6123,
        ),
        isNull,
      );
    });
  });

  group('mobileGatewayBindHostHint', () {
    test('hints wildcard binds toward explicit wss endpoints', () {
      final hint = mobileGatewayBindHostHint(bindHost: '0.0.0.0', port: 6768);
      expect(hint, contains('wss://'));
      expect(hint, contains('6768'));
    });

    test('hints non-loopback binds toward TLS or VPN', () {
      expect(
        mobileGatewayBindHostHint(bindHost: '192.168.1.10', port: 6768),
        contains('wss://'),
      );
    });

    test('returns no hint for loopback binds', () {
      expect(
        mobileGatewayBindHostHint(bindHost: '127.0.0.1', port: 6768),
        isNull,
      );
      expect(
        mobileGatewayBindHostHint(bindHost: 'localhost', port: 6768),
        isNull,
      );
    });
  });
}
