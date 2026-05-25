import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Single-select segmented control with Alera's tokenized shape and cursor
/// behavior. Wraps Material's [SegmentedButton] for the common case of one
/// required selection.
class AleraSegmentedButton<T> extends StatelessWidget {
  const AleraSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.dense = false,
    this.backgroundColor,
    this.foregroundColor,
    this.selectedBackgroundColor,
    this.selectedForegroundColor,
    this.borderColor,
    this.textStyle,
  });

  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelectionChanged;
  final bool dense;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? selectedBackgroundColor;
  final Color? selectedForegroundColor;
  final Color? borderColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        selectedBackgroundColor: selectedBackgroundColor,
        selectedForegroundColor: selectedForegroundColor,
        side: borderColor == null ? null : BorderSide(color: borderColor!),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        padding: dense
            ? const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space4,
              )
            : null,
        minimumSize: dense ? const Size(0, 30) : null,
        tapTargetSize: dense ? MaterialTapTargetSize.shrinkWrap : null,
        textStyle: textStyle,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
      segments: segments,
      selected: <T>{selected},
      onSelectionChanged: (selection) => onSelectionChanged(selection.first),
    );
  }
}
