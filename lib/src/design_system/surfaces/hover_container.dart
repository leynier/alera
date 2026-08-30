import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Animates a child's background between [baseColor] and [hoverColor] on
/// pointer hover, with a tokenized radius and fade. Use for tappable rows and
/// cells that should reveal an elevated surface under the cursor.
class const HoverContainer({
  super.key,
  required final Widget child,
  final Color hoverColor = AleraTokens.surfaceElevated,
  final Color baseColor = Colors.transparent,
  final double borderRadius = AleraTokens.radiusMd,
  final VoidCallback? onTap,
  final MouseCursor cursor = SystemMouseCursors.click,
  final EdgeInsets? padding,
}) extends StatefulWidget {
  @override
  State<HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<HoverContainer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.baseColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}
