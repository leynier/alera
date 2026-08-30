import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// One row of an [AleraActionSheet].
///
/// [leading] is a widget rather than an [IconData] so a caller can pass an
/// agent identity glyph instead of a Material icon.
class const AleraActionSheetEntry<T>({
  required final T value,
  required final String label,
  required final Widget leading,
});

/// Bottom sheet of mutually exclusive actions. Pops the tapped entry's value
/// from the [Navigator] and pops `null` when dismissed.
///
/// This is the phone counterpart of the desktop popup menu: rows are a full
/// tap target tall instead of the pointer-sized rows a popover can afford.
class const AleraActionSheet<T>({
  super.key,
  required final List<AleraActionSheetEntry<T>> entries,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          for (final entry in entries)
            ListTile(
              key: ValueKey<T>(entry.value),
              minTileHeight: AleraTokens.minTapTarget,
              leading: entry.leading,
              title: Text(entry.label),
              onTap: () => Navigator.of(context).pop(entry.value),
            ),
        ],
      ),
    );
  }
}

/// Shows [AleraActionSheet] and resolves with the chosen value, or `null` when
/// the sheet is dismissed without a choice.
Future<T?> showAleraActionSheet<T>(
  BuildContext context, {
  required List<AleraActionSheetEntry<T>> entries,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) => AleraActionSheet<T>(entries: entries),
  );
}
