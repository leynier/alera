import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Tappable row',
  group: 'Hover container',
  size: Size(240, 60),
)
Widget hoverContainerPreview() => HoverContainer(
  onTap: () {},
  padding: const .all(AleraTokens.space12),
  child: Text(
    'Hover me',
    style: const TextStyle(color: AleraTokens.foreground),
  ),
);

@AleraPreview(
  name: 'Keyboard focus',
  group: 'Hover container',
  size: Size(240, 120),
)
Widget hoverContainerFocusPreview() => Column(
  mainAxisSize: .min,
  children: <Widget>[
    for (final label in const <String>['Open Project', 'Clone Repository'])
      HoverContainer(
        onTap: () {},
        padding: const .all(AleraTokens.space12),
        child: Text(
          label,
          style: const TextStyle(color: AleraTokens.foreground),
        ),
      ),
  ],
);
