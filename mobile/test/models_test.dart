import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
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

    test('Accepts plaintext tailscale tailnet endpoints', () {
      final ipv4 = PairingOffer.fromJson(
        _offer(endpoint: 'ws://100.64.1.5:6768'),
      );
      final ipv6 = PairingOffer.fromJson(
        _offer(endpoint: 'ws://[fd7a:115c:a1e0:ab12::4]:6768'),
      );

      expect(ipv4.endpoint, 'ws://100.64.1.5:6768');
      expect(ipv6.endpoint, 'ws://[fd7a:115c:a1e0:ab12::4]:6768');
    });

    test('Rejects plaintext cgnat endpoints outside the tailscale range', () {
      expect(
        () => PairingOffer.fromJson(_offer(endpoint: 'ws://100.63.0.1:6768')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingOffer.fromJson(_offer(endpoint: 'ws://100.128.0.0:6768')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PairingOffer.fromJson(
          _offer(endpoint: 'ws://[fd7a:115c:a1e1::1]:6768'),
        ),
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

    test('Reloads saved tailscale endpoints', () {
      final profile = PairedHostProfile.fromJson(
        _profile(endpoint: 'ws://100.64.1.5:6768'),
      );

      expect(profile.endpoint, 'ws://100.64.1.5:6768');
    });

    test('Pairing result requires the runtime id promised by the offer', () {
      final offer = PairingOffer.fromJson(
        _offer(endpoint: 'ws://100.64.1.5:6768'),
      );

      expect(
        () => PairedHostProfile.fromPairingResult(
          offer,
          _credentials(runtimeId: 'runtime-other'),
        ),
        throwsA(isA<FormatException>()),
      );

      final profile = PairedHostProfile.fromPairingResult(
        offer,
        _credentials(runtimeId: 'runtime-1'),
      );
      expect(profile.runtimeId, 'runtime-1');
      expect(profile.id, 'runtime-1');
    });
  });
}

PairedDeviceCredentials _credentials({required String runtimeId}) {
  return PairedDeviceCredentials.fromJson(<String, Object?>{
    'deviceId': 'device-1',
    'displayName': 'My Phone',
    'runtimeId': runtimeId,
    'deviceToken': 'token-1',
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
