import 'package:alera_mobile/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingOffer', () {
    test('Accepts secure external endpoints', () {
      final offer = PairingOffer.fromJson(
        _offer(endpoint: 'wss://alera.example:6768'),
      );

      expect(offer.endpoint, 'wss://alera.example:6768');
    });

    test('Accepts plaintext loopback endpoints', () {
      final localhost = PairingOffer.fromJson(
        _offer(endpoint: 'ws://localhost:6768'),
      );
      final ipv6 = PairingOffer.fromJson(_offer(endpoint: 'ws://[::1]:6768'));

      expect(localhost.endpoint, 'ws://localhost:6768');
      expect(ipv6.endpoint, 'ws://[::1]:6768');
    });

    test('Rejects plaintext external endpoints', () {
      expect(
        () => PairingOffer.fromJson(_offer(endpoint: 'ws://192.168.1.10:6768')),
        throwsA(isA<FormatException>()),
      );
    });

    test('Rejects endpoints without explicit ports', () {
      expect(
        () => PairingOffer.fromJson(_offer(endpoint: 'wss://alera.example')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PairedHostProfile', () {
    test('Rejects saved plaintext external endpoints', () {
      expect(
        () => PairedHostProfile.fromJson(
          _profile(endpoint: 'ws://192.168.1.10:6768'),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, Object?> _offer({required String endpoint}) {
  return <String, Object?>{
    'v': aleraMobileProtocolVersion,
    'pairingId': 'pairing-1',
    'endpoint': endpoint,
    'runtimeId': 'runtime-1',
    'hostName': 'Alera Host',
    'pairingSecret': 'secret',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  };
}

Map<String, Object?> _profile({required String endpoint}) {
  return <String, Object?>{
    'id': 'runtime-1',
    'displayName': 'Alera Host',
    'endpoint': endpoint,
    'runtimeId': 'runtime-1',
    'deviceId': 'device-1',
    'pairedAt': DateTime.now().toUtc().toIso8601String(),
  };
}
