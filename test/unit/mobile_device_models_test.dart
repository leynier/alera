import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile device rejects an empty required identifier', () {
    expect(
      () => MobileDevice.fromJson(<String, Object?>{
        'id': ' ',
        'displayName': 'Phone',
        'permission': 'fullControl',
        'pairedAt': '2026-07-17T00:00:00.000Z',
      }),
      throwsFormatException,
    );
  });

  test('mobile pairing offer rejects an empty required identifier', () {
    expect(
      () => MobilePairingOffer.fromJson(<String, Object?>{
        'id': '',
        'endpoint': 'ws://127.0.0.1:6768',
        'createdAt': '2026-07-17T00:00:00.000Z',
        'expiresAt': '2026-07-17T00:10:00.000Z',
      }),
      throwsFormatException,
    );
  });
}
