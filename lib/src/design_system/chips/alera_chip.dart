import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Compact label chip.
///
/// - Without [onRemove]: a flat, square, low-emphasis tag (e.g. the project
///   name in front of a workspace row). Supports an optional [leading] icon
///   and [tooltip] to disambiguate categories (host, tag, …) and reveal
///   values that the chip truncates.
/// - With [onRemove]: a removable pill with a hover state and a close button
///   (e.g. a project added to a visibility filter).
class AleraChip extends StatefulWidget {
  const AleraChip({
    super.key,
    required this.label,
    this.onRemove,
    this.leading,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onRemove;
  final IconData? leading;
  final String? tooltip;

  @override
  State<AleraChip> createState() => _AleraChipState();
}

class _AleraChipState extends State<AleraChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.onRemove == null) {
      final label = Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AleraTokens.foregroundMuted,
          fontWeight: FontWeight.w500,
        ),
      );
      return _withTooltip(
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space2,
          ),
          decoration: BoxDecoration(
            color: AleraTokens.accentSubtle,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          child: widget.leading == null
              ? label
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      widget.leading,
                      size: 12,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    Flexible(child: label),
                  ],
                ),
        ),
      );
    }

    return _withTooltip(
      MouseRegion(
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
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: AleraTokens.space4),
              InkWell(
                onTap: widget.onRemove,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
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
