import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Compact label chip.
///
/// - Without [onRemove] or [onTap]: a flat, square, low-emphasis tag (e.g. the
///   project name in front of a workspace row). Supports an optional [leading]
///   icon and [tooltip] to disambiguate categories (host, tag, …) and reveal
///   values that the chip truncates.
/// - With [onTap]: a tappable tag with hover feedback (e.g. expand/collapse
///   child workspaces). Mutually exclusive with [onRemove].
/// - With [onRemove]: a removable pill with a hover state and a close button
///   (e.g. a project added to a visibility filter). Mutually exclusive with
///   [onTap].
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
  bool _hovered = false;

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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .opaque,
        onTap: widget.onTap,
        child: _buildStatic(
          theme,
          background: _hovered
              ? AleraTokens.surfaceElevated
              : AleraTokens.accentSubtle,
        ),
      ),
    );
  }

  Widget _buildRemovable(ThemeData theme) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AleraTokens.durationFast,
        padding: const EdgeInsets.only(
          left: AleraTokens.space8,
          right: AleraTokens.space4,
          top: AleraTokens.space2,
          bottom: AleraTokens.space2,
        ),
        decoration: BoxDecoration(
          color: _hovered
              ? AleraTokens.surfaceElevated
              : AleraTokens.accentSubtle,
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
              mouseCursor: SystemMouseCursors.click,
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
