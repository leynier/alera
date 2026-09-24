import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Overflowing strip',
  group: 'Horizontal scroll',
  size: Size(320, 80),
)
Widget aleraHorizontalScrollViewPreview() => const SizedBox(
  width: 220,
  height: AleraTokens.space32,
  child: AleraHorizontalScrollView(
    child: Row(
      mainAxisSize: .min,
      children: <Widget>[
        AleraChip(label: 'Explorer'),
        SizedBox(width: AleraTokens.space8),
        AleraChip(label: 'Search'),
        SizedBox(width: AleraTokens.space8),
        AleraChip(label: 'Source Control'),
        SizedBox(width: AleraTokens.space8),
        AleraChip(label: 'Pull Request'),
      ],
    ),
  ),
);
