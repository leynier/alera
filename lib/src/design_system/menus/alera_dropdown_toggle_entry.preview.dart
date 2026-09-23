import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_toggle_entry.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Menu',
  group: 'Dropdown Toggle Entry',
  size: Size(220, 160),
)
Widget aleraDropdownToggleEntryPreview() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: const Padding(
    padding: EdgeInsets.all(AleraTokens.space8),
    child: Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownToggleEntry<String>(
          label: 'Failed Checks',
          checked: true,
          onChanged: _ignoreValue,
        ),
        AleraDropdownToggleEntry<String>(
          label: 'Review Comments',
          checked: false,
          onChanged: _ignoreValue,
        ),
        AleraDropdownToggleEntry<String>(
          label: 'Disabled',
          checked: true,
          enabled: false,
          onChanged: _ignoreValue,
        ),
      ],
    ),
  ),
);

void _ignoreValue(bool _) {}
