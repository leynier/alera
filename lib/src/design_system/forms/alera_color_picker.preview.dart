import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_color_picker.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Color picker', group: 'Forms', size: Size(300, 240))
Widget aleraColorPickerPreview() =>
    AleraColorPicker(pickerColor: Colors.blue, onColorChanged: (_) {});

@AleraPreview(name: 'Color picker dialog', group: 'Forms', size: Size(200, 100))
Widget aleraColorPickerDialogPreview() {
  return Builder(
    builder: (BuildContext context) {
      return Center(
        child: FilledButton(
          onPressed: () {
            showAleraColorPickerDialog(
              context: context,
              initialColor: Colors.red,
              title: 'Choose color',
            );
          },
          child: const Text('Open Picker'),
        ),
      );
    },
  );
}
