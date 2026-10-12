import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_date_time_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Set', group: 'Date time field')
Widget aleraDateTimeFieldPreview() => AleraDateTimeField(
  labelText: 'Starts',
  value: DateTime(2026, 10, 13, 9),
  clearable: true,
  onChanged: (_) {},
);

@AleraPreview(name: 'Empty', group: 'Date time field')
Widget aleraDateTimeFieldEmptyPreview() =>
    AleraDateTimeField(labelText: 'Ends', value: null, onChanged: (_) {});
