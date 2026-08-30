import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Single-select segmented control with Alera's tokenized shape and cursor
/// behavior. Wraps Material's [SegmentedButton] for the common case of one
/// required selection.
class const AleraSegmentedButton<T>({
  super.key,
  required final List<ButtonSegment<T>> segments,
  required final T selected,
  required final ValueChanged<T> onSelectionChanged,
  final bool dense = false,
  final Color? backgroundColor,
  final Color? foregroundColor,
  final Color? selectedBackgroundColor,
  final Color? selectedForegroundColor,
  final Color? borderColor,
  final TextStyle? textStyle,
}) extends StatelessWidget {
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
