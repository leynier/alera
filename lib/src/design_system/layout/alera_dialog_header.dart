import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Header row for dialogs and popovers: a [title] on the left, an optional
/// [trailing] action, and a trailing close button wired to [onClose].
class const AleraDialogHeader({
  super.key,
  required final String title,
  required final VoidCallback onClose,
  final Widget? trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w600,
            ),
          ),
        ),
        ?trailing,
        AleraIconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: AleraIcons.close,
          minSize: 28,
        ),
      ],
    );
  }
}
