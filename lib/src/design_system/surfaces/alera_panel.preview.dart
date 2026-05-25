import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Settings group', group: 'Panel', size: Size(520, 200))
Widget aleraPanelPreview() => const AleraPanel(
  children: <Widget>[
    AleraSettingRow(
      title: 'Confirm before closing',
      description: 'Ask for confirmation when closing a workspace.',
      child: Switch(value: true, onChanged: null),
    ),
    AleraSettingRow(
      title: 'Restore previous session',
      child: Switch(value: false, onChanged: null),
    ),
  ],
);
