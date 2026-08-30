import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Structured Hover Card', group: 'Surfaces')
Widget aleraHoverCardPreview() => AleraHoverCard(
  semanticsLabel: 'Weekly quota, 72 percent left, resets in 1 day 3 hours',
  card: Container(
    width: 280,
    padding: const EdgeInsets.all(AleraTokens.space12),
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      border: Border.all(color: AleraTokens.border),
    ),
    child: const Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: <Widget>[
        Text('Weekly quota'),
        SizedBox(height: AleraTokens.space8),
        LinearProgressIndicator(value: 0.72),
        SizedBox(height: AleraTokens.space6),
        Text('72% left - resets in 1d 3h'),
      ],
    ),
  ),
  child: const Text('Hover or click for details'),
);
