import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Compact label chip.
///
/// - Without [onRemove] or [onTap]: a flat, low-emphasis tag.
/// - With [onTap]: a tappable tag. Mutually exclusive with [onRemove].
/// - With [onRemove]: a removable pill. Mutually exclusive with [onTap].
class const AleraChip({
  super.key,
  required final String label,
  final VoidCallback? onRemove,
  final VoidCallback? onTap,
  final IconData? leading,
  final IconData? trailing,
  final String? tooltip,
}) extends StatefulWidget {
  this
    : assert(
        onRemove == null || onTap == null,
        'AleraChip cannot be both removable and tappable',
      );

  @override
  State<AleraChip> createState() => _AleraChipState();
}

class _AleraChipState extends State<AleraChip> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.onRemove != null) {
      return _withTooltip(_buildRemovable(theme));
    }
    if (widget.onTap != null) {
      return _withTooltip(_buildTappable(theme));
    }
    return _withTooltip(_buildStatic(theme));
  }

  Widget _buildStatic(ThemeData theme, {Color? background}) {
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: .ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AleraTokens.foregroundMuted,
        fontWeight: .w500,
      ),
    );
    final hasIcons = widget.leading != null || widget.trailing != null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: background ?? AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: !hasIcons
          ? label
          : Row(
              mainAxisSize: .min,
              children: <Widget>[
                if (widget.leading != null) ...<Widget>[
                  Icon(
                    widget.leading,
                    size: 12,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                ],
                Flexible(child: label),
                if (widget.trailing != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space4),
                  Icon(
                    widget.trailing,
                    size: 12,
                    color: AleraTokens.foregroundMuted,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildTappable(ThemeData theme) {
    return GestureDetector(
      behavior: .opaque,
      onTap: widget.onTap,
      child: _buildStatic(theme),
    );
  }

  Widget _buildRemovable(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.only(
        left: AleraTokens.space8,
        right: AleraTokens.space4,
        top: AleraTokens.space2,
        bottom: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          Text(
            widget.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w500,
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          InkWell(
            onTap: widget.onRemove,
            borderRadius: .circular(AleraTokens.radiusPill),
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space2),
              child: Icon(
                AleraIcons.close,
                size: 12,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withTooltip(Widget child) {
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return child;
    }
    return Tooltip(message: tooltip, child: child);
  }
}
