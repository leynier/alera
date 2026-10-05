import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Drag to resize the sidebar; double-click to restore
/// [AleraTokens.sidebarDefaultWidth].
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
  Offset? _clickDownPosition;
  Duration? _lastClickUp;
  Offset? _lastClickPosition;

  @override
  Widget build(BuildContext context) {
    final emphasised = _hovered || _dragging;
    final handle = MouseRegion(
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
          width: AleraTokens.space6,
          child: Center(
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              width: emphasised
                  ? AleraTokens.strokeSm
                  : AleraTokens.dividerExtent,
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
    // A passive listener, not onDoubleTap: a double-tap recognizer would join
    // the gesture arena and delay the drag until it clears the touch slop.
    return Semantics(
      label: 'Resize Sidebar',
      hint: 'Double-click to reset the width',
      onTap: _resetWidth,
      child: Listener(
        onPointerDown: (event) => _clickDownPosition = event.position,
        onPointerUp: _handlePointerUp,
        child: handle,
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    final down = _clickDownPosition;
    _clickDownPosition = null;
    if (down == null || (event.position - down).distance > kTouchSlop) {
      _lastClickUp = null;
      return;
    }
    final previousUp = _lastClickUp;
    final previousPosition = _lastClickPosition;
    final isDoubleClick =
        previousUp != null &&
        previousPosition != null &&
        event.timeStamp - previousUp <= kDoubleTapTimeout &&
        (event.position - previousPosition).distance <= kDoubleTapSlop;
    if (isDoubleClick) {
      _lastClickUp = null;
      _resetWidth();
      return;
    }
    _lastClickUp = event.timeStamp;
    _lastClickPosition = event.position;
  }

  void _resetWidth() {
    const width = AleraTokens.sidebarDefaultWidth;
    widget.onResize(width);
    if (_dragging) {
      // The click's own drag end follows this pointer-up and commits it.
      _dragWidth = width;
    } else {
      widget.onResizeEnd?.call(width);
    }
  }

  void _stopDragging() {
    final finalWidth = _dragWidth ?? widget.currentWidth;
    _dragWidth = null;
    setState(() => _dragging = false);
    widget.onResizeEnd?.call(finalWidth);
  }
}
