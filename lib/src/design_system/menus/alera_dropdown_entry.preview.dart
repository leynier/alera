import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Menu', group: 'Dropdown Entry', size: Size(220, 140))
Widget aleraDropdownEntryPreview() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: const Padding(
    padding: EdgeInsets.all(AleraTokens.space8),
    child: Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownEntry<String>(value: 'flat', label: 'Flat List'),
        AleraDropdownEntry<String>(
          value: 'grouped',
          label: 'Grouped by Project',
          selected: true,
        ),
      ],
    ),
  ),
);

@AleraPreview(
  name: 'With Description',
  group: 'Dropdown Entry',
  size: Size(420, 180),
)
Widget aleraDropdownEntryDescriptionPreview() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: const Padding(
    padding: EdgeInsets.all(AleraTokens.space8),
    child: Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownEntry<String>(
          value: 'approval',
          label: 'Ask For Approval',
          description: 'Ask before running commands or changing files.',
          selected: true,
        ),
        AleraDropdownEntry<String>(
          value: 'full',
          label: 'Full Access',
          description:
              'Run commands, use the network and change files without asking.',
        ),
      ],
    ),
  ),
);
