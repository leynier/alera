import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Styled color picker widget wrapping [ColorPicker] from `flutter_colorpicker`.
///
/// Restricted to 6-character hex colors (no alpha channel) to match Alera's
/// terminal settings constraints.
class AleraColorPicker extends StatelessWidget {
  const AleraColorPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
  });

  final Color pickerColor;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return ColorPicker(
      pickerColor: pickerColor,
      onColorChanged: onColorChanged,
      enableAlpha: false,
      labelTypes: const [],
      portraitOnly: true,
      pickerAreaBorderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      colorPickerWidth: 260,
      pickerAreaHeightPercent: 0.7,
      paletteType: PaletteType.hsvWithHue,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                mainAxisAlignment: MainAxisAlignment.end,
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
