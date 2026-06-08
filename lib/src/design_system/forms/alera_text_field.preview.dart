import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Standard', group: 'Text field', size: Size(280, 80))
Widget aleraTextFieldStandardPreview() =>
    const AleraTextField(hintText: 'Workspace name');

@AleraPreview(name: 'Dense + prefix', group: 'Text field', size: Size(280, 80))
Widget aleraTextFieldDensePreview() => const AleraTextField(
  dense: true,
  prefixIcon: AleraIcons.add,
  hintText: 'Add project…',
);
