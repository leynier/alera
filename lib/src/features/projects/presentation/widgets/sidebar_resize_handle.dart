import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class const SidebarResizeHandle({
  super.key,
  required final double currentWidth,
  required final ValueChanged<double> onResize,
  final ValueChanged<double>? onResizeEnd,
}) extends StatefulWidget {
  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  double? _dragWidth;

  @override
  Widget build(BuildContext context) {
    final emphasised = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: .translucent,
        onHorizontalDragStart: (_) {
          _dragWidth = widget.currentWidth;
          setState(() => _dragging = true);
        },
        onHorizontalDragEnd: (_) => _stopDragging(),
        onHorizontalDragCancel: _stopDragging,
        onHorizontalDragUpdate: (details) {
          final next = (_dragWidth ?? widget.currentWidth) + details.delta.dx;
          _dragWidth = next;
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
    final finalWidth = _dragWidth ?? widget.currentWidth;
    _dragWidth = null;
    setState(() => _dragging = false);
    widget.onResizeEnd?.call(finalWidth);
  }
}
