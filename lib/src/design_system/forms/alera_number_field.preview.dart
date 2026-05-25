import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Font size', group: 'Number field', size: Size(240, 80))
Widget aleraNumberFieldPreview() => AleraNumberField(
  value: 13,
  min: 8,
  max: 32,
  step: 1,
  suffix: 'px',
  onChanged: (_) {},
);
