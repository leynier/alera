import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// One row of an [AleraActionSheet].
///
/// [leading] is a widget rather than an [IconData] so a caller can pass an
/// agent identity glyph instead of a Material icon. A [destructive] entry
/// paints its label and icon in the error color; a disabled one stays visible
/// so the sheet can say why an action is unavailable right now.
class const AleraActionSheetEntry<T>({
  required final T value,
  required final String label,
  required final Widget leading,
  final bool enabled = true,
  final bool destructive = false,
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
    // Scrolls once the rows outgrow the sheet: a long menu on a short phone
    // otherwise overflows past the bottom edge and clips its last actions.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            for (final entry in entries)
              ListTile(
                key: ValueKey<T>(entry.value),
                minTileHeight: AleraTokens.minTapTarget,
                leading: entry.leading,
                title: Text(entry.label),
                enabled: entry.enabled,
                iconColor: entry.destructive ? AleraTokens.error : null,
                textColor: entry.destructive ? AleraTokens.error : null,
                onTap: () => Navigator.of(context).pop(entry.value),
              ),
          ],
        ),
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
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (context) => AleraActionSheet<T>(entries: entries),
  );
}
