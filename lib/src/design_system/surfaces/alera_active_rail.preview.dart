import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Selected row', group: 'Active rail', size: Size(260, 140))
Widget aleraActiveRailPreview() => Container(
  width: 220,
  padding: const .all(AleraTokens.space6),
  decoration: BoxDecoration(
    color: AleraTokens.surfaceVariant,
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  ),
  child: Column(
    mainAxisSize: .min,
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final (index, label) in const <String>[
        'General',
        'Terminal',
        'Agents',
      ].indexed)
        AleraActiveRail(
          active: index == 1,
          child: HoverContainer(
            onTap: () {},
            baseColor: index == 1
                ? AleraActiveRail.selectedColor
                : Colors.transparent,
            borderRadius: AleraTokens.radiusSm,
            padding: const .symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space8,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: index == 1
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
            ),
          ),
        ),
    ],
  ),
);
