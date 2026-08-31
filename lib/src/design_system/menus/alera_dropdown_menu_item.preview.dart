import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_menu_item.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Actions',
  group: 'Dropdown Menu Item',
  size: Size(220, 150),
)
Widget aleraDropdownMenuItemPreview() => Material(
  color: AleraTokens.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    side: const BorderSide(color: AleraTokens.border),
  ),
  child: const Padding(
    padding: EdgeInsets.all(AleraTokens.space12),
    child: Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownMenuItem(label: 'Copy', onTap: _noop),
        AleraDropdownMenuItem(label: 'Select All', onTap: _noop),
      ],
    ),
  ),
);

void _noop() {}
