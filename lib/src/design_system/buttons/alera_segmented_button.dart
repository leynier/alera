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
  });

  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
      segments: segments,
      selected: <T>{selected},
      onSelectionChanged: (selection) => onSelectionChanged(selection.first),
    );
  }
}
