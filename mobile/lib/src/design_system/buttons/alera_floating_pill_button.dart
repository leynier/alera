import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Elevated pill that floats over scrolling content for one contextual action,
/// such as returning to the newest output.
class const AleraFloatingPillButton({
  super.key,
  required final String label,
  required final IconData icon,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AleraTokens.surfaceElevated,
      shape: const StadiumBorder(
        side: BorderSide(color: AleraTokens.borderSubtle),
      ),
      elevation: AleraTokens.spaceXs,
      shadowColor: AleraTokens.shadowSoft,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.spaceMd,
            vertical: AleraTokens.spaceSm,
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Icon(
                icon,
                size: AleraTokens.iconSm,
                color: AleraTokens.foreground,
              ),
              const SizedBox(width: AleraTokens.space6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
