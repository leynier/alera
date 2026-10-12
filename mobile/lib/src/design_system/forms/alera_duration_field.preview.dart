import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_duration_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Minutes', group: 'Duration field')
Widget aleraDurationFieldPreview() => AleraDurationField(
  labelText: 'Inactivity Timeout',
  seconds: 900,
  onChanged: (_) {},
);

@AleraPreview(name: 'Error', group: 'Duration field')
Widget aleraDurationFieldErrorPreview() => AleraDurationField(
  labelText: 'Precheck Timeout',
  seconds: 5,
  units: const <AleraDurationUnit>[
    AleraDurationUnit.seconds,
    AleraDurationUnit.minutes,
  ],
  errorText: 'Use at least 10 seconds.',
  onChanged: (_) {},
);
