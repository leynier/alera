import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_compact_input.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Framed', group: 'Compact input', size: Size(260, 120))
Widget aleraCompactInputPreview() => AleraCompactFieldFrame(
  labelText: 'Retry Attempts',
  errorText: 'Use a whole number.',
  child: AleraCompactInput(
    controller: TextEditingController(text: '2.5'),
    hasError: true,
  ),
);
