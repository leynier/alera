import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Default', group: 'Icon button')
Widget aleraIconButtonPreview() =>
    AleraIconButton(tooltip: 'Close', icon: Icons.close, onPressed: () {});

@AleraPreview(name: 'Larger hit area', group: 'Icon button')
Widget aleraIconButtonLargePreview() => AleraIconButton(
  tooltip: 'Add',
  icon: Icons.add,
  iconSize: 18,
  minSize: 34,
  onPressed: () {},
);
