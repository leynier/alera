import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_floating_pill_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Jump To Latest', group: 'Buttons')
Widget aleraFloatingPillButtonPreview() => AleraFloatingPillButton(
  label: 'Jump To Latest',
  icon: AleraIcons.chevronDown,
  onPressed: () {},
);
