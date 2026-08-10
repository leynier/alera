import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Dropdown-style interactive row for compact action menus.
class AleraDropdownMenuItem extends StatelessWidget {
  const AleraDropdownMenuItem({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.selected = false,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool selected;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final itemEnabled = enabled && onTap != null;
    final color = itemEnabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    return MouseRegion(
      cursor: itemEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: SizedBox(
        height: AleraTokens.space32 + AleraTokens.space4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2 / 2),
          child: InkWell(
            autofocus: autofocus,
            onTap: itemEnabled ? onTap : null,
            mouseCursor: itemEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading!,
                    const SizedBox(width: AleraTokens.space8),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: color),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      AleraIcons.check,
                      size: AleraTokens.space16,
                      color: AleraTokens.foreground,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
