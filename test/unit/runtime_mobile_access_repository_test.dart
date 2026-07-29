import 'dart:async';

import 'package:alera/src/features/mobile_devices/domain/mobile_access_status.dart';
import 'package:alera/src/features/mobile_devices/infra/runtime_mobile_access_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeMobileAccessRepository', () {
    test('status parses the full mobile status payload', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['mobile.status.get'] = _statusPayload();
      final repository = RuntimeMobileAccessRepository(client);

      final status = await repository.status();

      expect(status.protocolVersion, 1);
      expect(status.settings.enabled, isTrue);
      expect(status.settings.bindHost, '127.0.0.1');
      expect(status.settings.port, 6768);
      expect(status.runtimeHostActive, isTrue);
      expect(status.devices, hasLength(2));
      expect(status.devices.first.displayName, 'Phone');
      expect(status.devices.first.isRevoked, isFalse);
      expect(status.devices.last.isRevoked, isTrue);
      expect(status.activePairings, hasLength(1));
      expect(status.activePairings.first.endpoint, 'ws://127.0.0.1:6768');
    });

    test(
      'status tolerates payloads without endpoint mode or tailscale',
      () async {
        final client = _FakeRuntimeHostClient();
        client.responses['mobile.status.get'] = _statusPayload();
        final repository = RuntimeMobileAccessRepository(client);

        final status = await repository.status();

        expect(status.settings.endpointMode, MobileEndpointMode.loopback);
        expect(status.tailscale, isNull);
      },
    );

    test('status parses endpoint mode and tailscale detection', () async {
      final client = _FakeRuntimeHostClient();
      final payload = _statusPayload();
      (payload['settings']! as Map<String, Object?>)['endpointMode'] =
          'tailscale';
      payload['tailscale'] = <String, Object?>{
        'detected': true,
        'running': true,
        'tailnetIp': '100.101.102.103',
      };
      client.responses['mobile.status.get'] = payload;
      final repository = RuntimeMobileAccessRepository(client);

      final status = await repository.status();

      expect(status.settings.endpointMode, MobileEndpointMode.tailscale);
      expect(status.tailscale, isNotNull);
      expect(status.tailscale!.detected, isTrue);
      expect(status.tailscale!.running, isTrue);
      expect(status.tailscale!.tailnetIp, '100.101.102.103');
      expect(status.tailscale!.error, isNull);
    });

    test('watchStatus coalesces a burst of mobile change events', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['mobile.status.get'] = _statusPayload();
      final repository = RuntimeMobileAccessRepository(client);

      final received = <MobileAccessStatus>[];
      final subscription = repository.watchStatus().listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(received, hasLength(1), reason: 'initial fetch');

      for (final name in <String>[
        'mobileSettingsChanged',
        'mobilePairingsChanged',
        'mobileDevicesChanged',
        'mobileGatewayChanged',
        'projectsChanged',
      ]) {
        client.emit(RuntimeHostEvent(name, const <String, Object?>{}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // The four mobile events collapse into a single refetch; the non-mobile
      // event must not trigger one at all.
      expect(received, hasLength(2));
      expect(
        client.requests.where((type) => type == 'mobile.status.get'),
        hasLength(2),
      );
    });

    test('updateSettings sends only the provided fields', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['mobile.settings.update'] = <String, Object?>{
        'enabled': true,
        'bindHost': '0.0.0.0',
        'port': 7000,
      };
      final repository = RuntimeMobileAccessRepository(client);

      final settings = await repository.updateSettings(
        enabled: true,
        port: 7000,
      );

      expect(settings.enabled, isTrue);
      expect(settings.port, 7000);
      expect(client.payloads['mobile.settings.update']!.single, {
        'enabled': true,
        'port': 7000,
      });
    });

    test('updateSettings sends the endpoint mode when provided', () async {
      final client = _FakeRuntimeHostClient();
      client.responses['mobile.settings.update'] = <String, Object?>{
        'enabled': true,
        'bindHost': '100.101.102.103',
        'port': 6768,
        'endpointMode': 'tailscale',
      };
      final repository = RuntimeMobileAccessRepository(client);

      final settings = await repository.updateSettings(
        enabled: true,
        endpointMode: MobileEndpointMode.tailscale,
      );

      expect(settings.endpointMode, MobileEndpointMode.tailscale);
      expect(settings.bindHost, '100.101.102.103');
      expect(client.payloads['mobile.settings.update']!.single, {
        'enabled': true,
        'endpointMode': 'tailscale',
      });
    });

    test(
      'createPairingOffer returns a grant that round-trips the payload',
      () async {
        final client = _FakeRuntimeHostClient();
        client.responses['mobile.pairing.create'] = <String, Object?>{
          'v': 1,
          'pairingId': 'offer-1',
          'endpoint': 'wss://alera.example.test:6768',
          'runtimeId': 'runtime-1',
          'hostName': 'Test Host',
          'pairingSecret': 'secret',
          'serverPublicKeyB64': null,
          'expiresAt': '2026-07-17T00:10:00.000Z',
        };
        final repository = RuntimeMobileAccessRepository(client);

        final grant = await repository.createPairingOffer(
          endpoint: 'wss://alera.example.test:6768',
          deviceName: 'My Phone',
          expiresMinutes: 5,
        );

        expect(grant.pairingId, 'offer-1');
        expect(grant.hostName, 'Test Host');
        expect(grant.toQrJson(), contains('"pairingSecret":"secret"'));
        expect(grant.toQrJson(), contains('"v":1'));
        expect(client.payloads['mobile.pairing.create']!.single, {
          'endpoint': 'wss://alera.example.test:6768',
          'deviceName': 'My Phone',
          'expiresMinutes': 5,
        });
      },
    );

    test(
      'cancel, rename, revoke, and delete send the expected payloads',
      () async {
        final client = _FakeRuntimeHostClient();
        client.responses['mobile.device.rename'] = _devicePayload(
          id: 'device-1',
          displayName: 'Renamed',
        );
        final repository = RuntimeMobileAccessRepository(client);

        await repository.cancelPairingOffer('offer-1');
        final renamed = await repository.renameDevice(
          id: 'device-1',
          displayName: 'Renamed',
        );
        await repository.revokeDevice('device-1');
        await repository.deleteDevice('device-1');

        expect(renamed.displayName, 'Renamed');
        expect(client.payloads['mobile.pairing.cancel']!.single, {
          'id': 'offer-1',
        });
        expect(client.payloads['mobile.device.rename']!.single, {
          'id': 'device-1',
          'displayName': 'Renamed',
        });
        expect(client.payloads['mobile.device.revoke']!.single, {
          'id': 'device-1',
        });
        expect(client.payloads['mobile.device.delete']!.single, {
          'id': 'device-1',
        });
      },
    );
  });
}

Map<String, Object?> _statusPayload() {
  return <String, Object?>{
    'protocolVersion': 1,
    'settings': <String, Object?>{
      'enabled': true,
      'bindHost': '127.0.0.1',
      'port': 6768,
      'serverPublicKeyB64': null,
      'updatedAt': '2026-07-17T00:00:00.000Z',
    },
    'devices': <Object?>[
      _devicePayload(id: 'device-1', displayName: 'Phone'),
      _devicePayload(
        id: 'device-2',
        displayName: 'Old Phone',
        revokedAt: '2026-07-16T00:00:00.000Z',
      ),
    ],
    'activePairings': <Object?>[
      <String, Object?>{
        'id': 'offer-1',
        'endpoint': 'ws://127.0.0.1:6768',
        'expectedDeviceName': null,
        'serverPublicKeyB64': null,
        'createdAt': '2026-07-17T00:00:00.000Z',
        'expiresAt': '2026-07-17T00:10:00.000Z',
      },
    ],
    'runtimeHostActive': true,
  };
}

Map<String, Object?> _devicePayload({
  required String id,
  required String displayName,
  String? revokedAt,
}) {
  return <String, Object?>{
    'id': id,
    'displayName': displayName,
    'publicKeyB64': null,
    'permission': 'fullControl',
    'pairedAt': '2026-07-15T00:00:00.000Z',
    'lastSeenAt': '2026-07-16T12:00:00.000Z',
    'revokedAt': revokedAt,
  };
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final requests = <String>[];
  final payloads = <String, List<Map<String, Object?>>>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(type);
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    return responses[type];
  }

  void emit(RuntimeHostEvent event) {
    _events.add(event);
  }

  void close() {
    _events.close();
  }
}
