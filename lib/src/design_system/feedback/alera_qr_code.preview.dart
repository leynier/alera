import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_qr_code.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Pairing Payload', group: 'QR code')
Widget aleraQrCodePairingPreview() => const AleraQrCode(
  data:
      '{"v":1,"pairingId":"a1b2c3","endpoint":"wss://alera.example.test:6768",'
      '"runtimeId":"runtime-1","hostName":"Alera Runtime",'
      '"pairingSecret":"secret","expiresAt":"2030-01-01T00:00:00Z"}',
);

@AleraPreview(name: 'Small', group: 'QR code')
Widget aleraQrCodeSmallPreview() =>
    const AleraQrCode(data: 'wss://alera.example.test:6768', size: 140);
