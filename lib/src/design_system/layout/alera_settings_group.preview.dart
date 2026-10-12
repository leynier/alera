import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Group', group: 'Settings group', size: Size(520, 220))
Widget aleraSettingsGroupPreview() => const SizedBox(
  width: 480,
  child: AleraSettingsGroup(
    title: 'Safety',
    description: 'Confirmation prompts for destructive workspace actions.',
    children: <Widget>[
      AleraSettingRow(
        title: 'Confirm Project Removal',
        description: 'Ask before unregistering a project.',
        child: Align(
          alignment: Alignment.centerRight,
          child: Switch(value: true, onChanged: _ignoreValue),
        ),
      ),
      AleraSettingRow(
        title: 'Confirm Workspace Removal',
        description: 'Ask before removing a linked workspace.',
        child: Align(
          alignment: Alignment.centerRight,
          child: Switch(value: false, onChanged: _ignoreValue),
        ),
      ),
    ],
  ),
);

void _ignoreValue(bool _) {}

@AleraPreview(
  name: 'Collapsible',
  group: 'Settings group',
  size: Size(520, 200),
)
Widget aleraSettingsGroupCollapsiblePreview() => SizedBox(
  width: 480,
  child: AleraSettingsGroup(
    title: 'Advanced',
    description: 'Install directory and platform overrides.',
    collapsible: true,
    initiallyExpanded: false,
    trailing: TextButton(onPressed: () {}, child: const Text('Revert')),
    children: const <Widget>[
      AleraSettingRow(
        title: 'Install Directory',
        description: 'Where the Alera runtime lives on the host.',
        child: Text('~/.alera/runtime'),
      ),
    ],
  ),
);
