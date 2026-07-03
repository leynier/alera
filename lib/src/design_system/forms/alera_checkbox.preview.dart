import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'States', group: 'Checkbox', size: Size(280, 160))
Widget aleraCheckboxPreview() => const Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    AleraCheckbox(value: true, onChanged: _ignoreValue, label: 'Overwrite'),
    AleraCheckbox(value: false, onChanged: _ignoreValue, label: 'Overwrite'),
    AleraCheckbox(
      value: true,
      onChanged: _ignoreValue,
      label: 'Disabled',
      enabled: false,
    ),
    AleraCheckbox(value: false, onChanged: _ignoreValue),
  ],
);

void _ignoreValue(bool _) {}
