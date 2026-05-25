import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Idle', group: 'Menu item', size: Size(220, 40))
Widget aleraMenuItemIdlePreview() =>
    AleraMenuItem(label: 'Solarized Dark', selected: false, onTap: () {});

@AleraPreview(name: 'Selected', group: 'Menu item', size: Size(220, 40))
Widget aleraMenuItemSelectedPreview() =>
    AleraMenuItem(label: 'Solarized Dark', selected: true, onTap: () {});

@AleraPreview(name: 'Active', group: 'Menu item', size: Size(220, 40))
Widget aleraMenuItemActivePreview() => AleraMenuItem(
  label: 'Solarized Dark',
  selected: false,
  active: true,
  onTap: () {},
);
