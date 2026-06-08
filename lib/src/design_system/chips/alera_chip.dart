import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Compact label chip.
///
/// - Without [onRemove]: a flat, square, low-emphasis tag (e.g. the project
///   name in front of a workspace row).
/// - With [onRemove]: a removable pill with a hover state and a close button
///   (e.g. a project added to a visibility filter).
class AleraChip extends StatefulWidget {
  const AleraChip({super.key, required this.label, this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  State<AleraChip> createState() => _AleraChipState();
}

class _AleraChipState extends State<AleraChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.onRemove == null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: AleraTokens.space2,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.accentSubtle,
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

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
    );
  }
}
