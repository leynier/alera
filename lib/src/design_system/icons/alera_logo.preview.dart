import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_logo.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Sizes', group: 'Logo')
Widget aleraLogoPreview() => const Row(
  mainAxisSize: .min,
  spacing: AleraTokens.space16,
  children: <Widget>[
    AleraLogo(size: AleraTokens.logoSm),
    AleraLogo(),
    AleraLogo(size: AleraTokens.logoLg),
  ],
);
