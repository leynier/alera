import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_color_picker.dart';
import 'package:flutter/material.dart';

/// Small bordered square that previews a single color. Used next to color
/// inputs (e.g. terminal palette overrides).
///
/// Can optionally accept an [onColorChanged] callback. If provided, tapping
/// the swatch automatically opens Alera's styled color picker dialog and
/// triggers the callback with the selected color.
class AleraColorSwatch extends StatelessWidget {
  const AleraColorSwatch({
    super.key,
    required this.color,
    this.size = 30,
    this.onColorChanged,
    this.pickerTitle = 'Choose color',
  });

  final Color color;
  final double size;
  final ValueChanged<Color>? onColorChanged;
  final String pickerTitle;

  Future<void> _openPicker(BuildContext context) async {
    if (onColorChanged == null) return;
    final selectedColor = await showAleraColorPickerDialog(
      context: context,
      initialColor: color,
      title: pickerTitle,
    );
    if (selectedColor != null) {
      onColorChanged!(selectedColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final swatch = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
    );

    if (onColorChanged == null) {
      return swatch;
    }

    return Tooltip(
      message: 'Select color',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPicker(context),
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          mouseCursor: SystemMouseCursors.click,
          child: swatch,
        ),
      ),
    );
  }
}
