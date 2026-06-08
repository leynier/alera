import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Three options', group: 'Segmented button')
Widget aleraSegmentedButtonPreview() => AleraSegmentedButton<int>(
  selected: 0,
  onSelectionChanged: (_) {},
  segments: const <ButtonSegment<int>>[
    ButtonSegment<int>(value: 0, icon: Icon(AleraIcons.square)),
    ButtonSegment<int>(value: 1, icon: Icon(AleraIcons.text)),
    ButtonSegment<int>(value: 2, icon: Icon(AleraIcons.remove)),
  ],
);
