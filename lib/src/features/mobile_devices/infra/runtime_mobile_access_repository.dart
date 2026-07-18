import 'dart:async';

import 'package:alera/src/features/mobile_devices/domain/mobile_access_status.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const Set<String> _mobileChangeEventNames = <String>{
  'mobileSettingsChanged',
  'mobilePairingsChanged',
  'mobileDevicesChanged',
  'mobileGatewayChanged',
};

class RuntimeMobileAccessRepository {
  RuntimeMobileAccessRepository(this._client);

  final RuntimeHostClient _client;

  Future<MobileAccessStatus> status() async {
    final payload = await _client.runtimeRequest('mobile.status.get');
    return MobileAccessStatus.fromJson(_mapFromPayload(payload));
  }

  Stream<MobileAccessStatus> watchStatus() async* {
    yield await status();
    await for (final event in _client.runtimeEvents) {
      if (_mobileChangeEventNames.contains(event.name)) {
        yield await status();
      }
    }
  }

  Future<MobileGatewaySettings> updateSettings({
    bool? enabled,
    String? bindHost,
    int? port,
  }) async {
    final payload = await _client
        .runtimeRequest('mobile.settings.update', <String, Object?>{
          'enabled': ?enabled,
          'bindHost': ?bindHost,
          'port': ?port,
        });
    return MobileGatewaySettings.fromJson(_mapFromPayload(payload));
  }

  Future<MobilePairingOfferGrant> createPairingOffer({
    String? endpoint,
    String? deviceName,
    int? expiresMinutes,
  }) async {
    final payload = await _client
        .runtimeRequest('mobile.pairing.create', <String, Object?>{
          'endpoint': ?endpoint,
          'deviceName': ?deviceName,
          'expiresMinutes': ?expiresMinutes,
        });
    return MobilePairingOfferGrant.fromJson(_mapFromPayload(payload));
  }

  Future<void> cancelPairingOffer(String id) async {
    await _client.runtimeRequest('mobile.pairing.cancel', <String, Object?>{
      'id': id,
    });
  }

  Future<MobileDevice> renameDevice({
    required String id,
    required String displayName,
  }) async {
    final payload = await _client
        .runtimeRequest('mobile.device.rename', <String, Object?>{
          'id': id,
          'displayName': displayName,
        });
    return MobileDevice.fromJson(_mapFromPayload(payload));
  }

  Future<void> revokeDevice(String id) async {
    await _client.runtimeRequest('mobile.device.revoke', <String, Object?>{
      'id': id,
    });
  }
}

Map<String, Object?> _mapFromPayload(Object? payload) {
  if (payload is Map) {
    return Map<String, Object?>.from(payload);
  }
  throw const FormatException(
    'Runtime mobile access payload must be a JSON object.',
  );
}
