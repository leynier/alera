import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Accent', group: 'Color swatch')
Widget aleraColorSwatchPreview() =>
    const AleraColorSwatch(color: AleraTokens.accent);

@AleraPreview(name: 'Success', group: 'Color swatch')
Widget aleraColorSwatchSuccessPreview() =>
    const AleraColorSwatch(color: AleraTokens.success);
