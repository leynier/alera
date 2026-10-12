import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Morning', group: 'Time of day field')
Widget aleraTimeOfDayFieldPreview() => AleraTimeOfDayField(
  labelText: 'Time',
  hour: 9,
  minute: 30,
  onChanged: (_, _) {},
);
