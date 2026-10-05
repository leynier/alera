import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Selected Row', group: 'Active Rail')
Widget aleraActiveRailPreview() => Padding(
  padding: AleraTokens.pagePadding,
  child: Column(
    mainAxisSize: .min,
    children: <Widget>[
      for (final (index, label) in const <String>[
        'main',
        'feat/active-rail',
        'fix/badge-tones',
      ].indexed)
        AleraActiveRail(
          active: index == 1,
          child: ListTile(
            tileColor: index == 1 ? AleraActiveRail.selectedColor : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            ),
            title: Text(label),
            onTap: () {},
          ),
        ),
    ],
  ),
);
