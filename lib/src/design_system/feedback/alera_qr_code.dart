import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Renders [data] as a scannable QR symbol. Alera is dark-only, so the QR
/// sits on its own light surface island: camera scanners need dark modules on
/// a light background with a quiet zone, which the app theme cannot provide.
class AleraQrCode extends StatelessWidget {
  const AleraQrCode({super.key, required this.data, this.size = 240});

  final String data;
  final double size;

  // Scannability rule: near-black modules on white, independent of theme.
  static const Color _moduleColor = Color(0xFF111111);
  static const Color _quietZoneColor = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(AleraTokens.space16),
      decoration: BoxDecoration(
        color: _quietZoneColor,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: PrettyQrView.data(
        data: data,
        decoration: const PrettyQrDecoration(
          shape: PrettyQrSmoothSymbol(color: _moduleColor, roundFactor: 0),
        ),
      ),
    );
  }
}
