import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Removable chip rendered in the view-options modal to represent a project
/// the user has added to the visibility filter.
class SelectedProjectChip extends StatefulWidget {
  const SelectedProjectChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  State<SelectedProjectChip> createState() => _SelectedProjectChipState();
}

class _SelectedProjectChipState extends State<SelectedProjectChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                  Icons.close,
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
