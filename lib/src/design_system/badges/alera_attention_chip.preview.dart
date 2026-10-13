import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_attention_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Tones', group: 'Attention chip', size: Size(320, 80))
Widget aleraAttentionChipPreview() => Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraAttentionChip(
      icon: AleraIcons.workspaceChildren,
      count: 0,
      tooltip: 'Open Activity',
      onPressed: () {},
    ),
    AleraAttentionChip(
      icon: AleraIcons.workspaceChildren,
      count: 2,
      tone: .accent,
      tooltip: 'Open Activity · 2 items need attention',
      onPressed: () {},
    ),
    AleraAttentionChip(
      icon: AleraIcons.workspaceChildren,
      count: 1200,
      tone: .warning,
      tooltip: 'Open Activity · 1200 items need attention',
      onPressed: () {},
    ),
  ],
);
