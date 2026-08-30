import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Styled color picker widget wrapping [ColorPicker] from `flutter_colorpicker`.
///
/// Restricted to 6-character hex colors (no alpha channel) to match Alera's
/// terminal settings constraints.
class const AleraColorPicker({
  super.key,
  required final Color pickerColor,
  required final ValueChanged<Color> onColorChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColorPicker(
      pickerColor: pickerColor,
      onColorChanged: onColorChanged,
      enableAlpha: false,
      labelTypes: const [],
      portraitOnly: true,
      pickerAreaBorderRadius: .circular(AleraTokens.radiusLg),
      colorPickerWidth: 260,
      pickerAreaHeightPercent: 0.7,
      paletteType: .hsvWithHue,
    );
  }
}

/// Modal dialog helper that displays [AleraColorPicker] and returns the selected color.
Future<Color?> showAleraColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  required String title,
}) {
  return showDialog<Color>(
    context: context,
    builder: (BuildContext context) {
      Color selectedColor = initialColor;
      final theme = Theme.of(context);
      return AleraDialog(
        maxWidth: 300,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w600),
              ),
              const SizedBox(height: AleraTokens.space16),
              Align(
                alignment: Alignment.center,
                child: AleraColorPicker(
                  pickerColor: initialColor,
                  onColorChanged: (Color color) {
                    selectedColor = color;
                  },
                ),
              ),
              const SizedBox(height: AleraTokens.space20),
              Row(
                mainAxisAlignment: .end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(selectedColor),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
