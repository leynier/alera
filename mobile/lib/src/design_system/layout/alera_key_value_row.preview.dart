import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Facts', group: 'Key value row')
Widget aleraKeyValueRowPreview() => const Column(
  mainAxisSize: .min,
  children: <Widget>[
    AleraKeyValueRow(
      icon: AleraIcons.schedule,
      label: 'Schedule',
      value: 'Weekdays at 09:00',
    ),
    AleraKeyValueRow(
      icon: AleraIcons.folder,
      label: 'Destination',
      value: 'New tab in alera / main',
      trailing: AleraBadge(label: 'Active', tone: .success),
    ),
    AleraKeyValueRow(label: 'Id', value: 'auto_01HZX4', monospace: true),
  ],
);
