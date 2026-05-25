import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Switch row', group: 'Setting row', size: Size(520, 90))
Widget aleraSettingRowPreview() => const AleraSettingRow(
  title: 'Confirm before closing',
  description: 'Ask for confirmation when closing a workspace.',
  child: Switch(value: true, onChanged: null),
);
