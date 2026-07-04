import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Selected', group: 'Dropdown field', size: Size(280, 90))
Widget aleraDropdownFieldPreview() => const SizedBox(
  width: 220,
  child: AleraDropdownField<String>(
    value: 'agent',
    entries: <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: 'agent', label: 'SSH Agent'),
      AleraDropdownFieldEntry<String>(value: 'key', label: 'Private Key'),
      AleraDropdownFieldEntry<String>(
        value: 'password',
        label: 'Password',
        enabled: false,
      ),
    ],
    onChanged: _ignoreValue,
  ),
);

@AleraPreview(name: 'Placeholder', group: 'Dropdown field', size: Size(280, 90))
Widget aleraDropdownFieldPlaceholderPreview() => const SizedBox(
  width: 220,
  child: AleraDropdownField<String>(
    value: null,
    hintText: 'Select An Option',
    entries: <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: 'auto', label: 'Auto'),
      AleraDropdownFieldEntry<String>(value: 'macos', label: 'macOS'),
      AleraDropdownFieldEntry<String>(value: 'linux', label: 'Linux'),
    ],
    onChanged: _ignoreValue,
  ),
);

@AleraPreview(name: 'Labeled', group: 'Dropdown field', size: Size(280, 110))
Widget aleraDropdownFieldLabeledPreview() => const SizedBox(
  width: 220,
  child: AleraDropdownField<String>(
    value: 'agent',
    labelText: 'Auth Method',
    entries: <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: 'agent', label: 'SSH Agent'),
      AleraDropdownFieldEntry<String>(value: 'key', label: 'Private Key'),
    ],
    onChanged: _ignoreValue,
  ),
);

@AleraPreview(name: 'Disabled', group: 'Dropdown field', size: Size(280, 90))
Widget aleraDropdownFieldDisabledPreview() => const SizedBox(
  width: 220,
  child: AleraDropdownField<String>(
    value: 'auto',
    enabled: false,
    entries: <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: 'auto', label: 'Auto'),
    ],
    onChanged: _ignoreValue,
  ),
);

void _ignoreValue(String _) {}
