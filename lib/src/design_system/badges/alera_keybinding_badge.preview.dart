import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Chord', group: 'Keybinding badge')
Widget aleraKeybindingBadgePreview() =>
    const AleraKeybindingBadge(label: 'Ctrl+Shift+P');

@AleraPreview(name: 'macOS glyphs', group: 'Keybinding badge')
Widget aleraKeybindingBadgeMacPreview() => const Wrap(
  spacing: AleraTokens.space4,
  children: <Widget>[
    AleraKeybindingBadge(label: '⌘K'),
    AleraKeybindingBadge(label: '⌘⇧P'),
  ],
);
