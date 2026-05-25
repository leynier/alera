import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({
    super.key,
    required this.currentWidth,
    required this.onResize,
  });

  final double currentWidth;
  final ValueChanged<double> onResize;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final emphasised = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => _stopDragging(),
        onHorizontalDragCancel: _stopDragging,
        onHorizontalDragUpdate: (details) {
          final next = widget.currentWidth + details.delta.dx;
          widget.onResize(next);
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              width: emphasised ? 2 : 1,
              decoration: BoxDecoration(
                color: emphasised
                    ? AleraTokens.border
                    : AleraTokens.borderSubtle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    setState(() => _dragging = false);
  }
}
