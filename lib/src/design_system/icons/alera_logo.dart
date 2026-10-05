import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// The white Alera mark, square at [size]. Use the `logo*` tokens for size.
class const AleraLogo({super.key, final double size = AleraTokens.logoMd})
    extends StatelessWidget {
  static const String assetPath = 'assets/logo/alera-logo-white.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      filterQuality: .medium,
      excludeFromSemantics: true,
    );
  }
}
