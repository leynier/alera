import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_submenu_entry.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Menu',
  group: 'Dropdown Submenu Entry',
  size: Size(240, 80),
)
Widget aleraDropdownSubmenuEntryPreview() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: const Padding(
    padding: EdgeInsets.all(AleraTokens.space8),
    child: AleraDropdownSubmenuEntry<String>(
      leading: Icon(AleraIcons.folder, size: 16),
      label: 'Set Section',
      items: <PopupMenuEntry<String>>[],
      enabled: false,
    ),
  ),
);
