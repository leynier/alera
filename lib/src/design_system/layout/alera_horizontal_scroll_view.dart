import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Maps a vertical mouse wheel onto a horizontal [ScrollPosition].
///
/// Flutter reads [PointerScrollEvent.scrollDelta.dx] for [Axis.horizontal]
/// unless Shift is held, so a plain wheel over a tab strip or toolbar does
/// nothing. Trackpads already send [scrollDelta.dx]; Shift+wheel keeps the
/// framework's built-in axis flip. This listener claims only the leftover
/// case: a mouse wheel with no horizontal delta over a horizontal strip that
/// can actually move.
class const AleraMouseWheelHorizontalScroll({
  super.key,
  required this.controller,
  required this.child,
}) extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) =>
          claimMouseWheelForHorizontalScroll(event, controller),
      child: child,
    );
  }
}

/// Horizontal [SingleChildScrollView] that also scrolls from a vertical mouse
/// wheel. Prefer this over a bare horizontal [SingleChildScrollView] for
/// desktop strips that have no vertical overflow of their own.
class const AleraHorizontalScrollView({
  super.key,
  this.controller,
  this.padding,
  this.reverse = false,
  this.physics,
  this.clipBehavior = Clip.hardEdge,
  required this.child,
}) extends StatefulWidget {
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final bool reverse;
  final ScrollPhysics? physics;
  final Clip clipBehavior;
  final Widget child;

  @override
  State<AleraHorizontalScrollView> createState() =>
      _AleraHorizontalScrollViewState();
}

class _AleraHorizontalScrollViewState extends State<AleraHorizontalScrollView> {
  ScrollController? _owned;

  ScrollController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    _syncOwnedController();
  }

  @override
  void didUpdateWidget(covariant AleraHorizontalScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _syncOwnedController();
    }
  }

  void _syncOwnedController() {
    if (widget.controller == null) {
      _owned ??= ScrollController();
      return;
    }
    _owned?.dispose();
    _owned = null;
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraMouseWheelHorizontalScroll(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: .horizontal,
        reverse: widget.reverse,
        padding: widget.padding,
        physics: widget.physics,
        clipBehavior: widget.clipBehavior,
        child: widget.child,
      ),
    );
  }
}

/// Claims [event] for [controller] when a vertical mouse wheel should move a
/// horizontal strip.
@visibleForTesting
void claimMouseWheelForHorizontalScroll(
  PointerSignalEvent event,
  ScrollController controller,
) {
  if (event is! PointerScrollEvent) {
    return;
  }
  final delta = horizontalMouseWheelDelta(event);
  if (delta == null) {
    return;
  }
  if (!controller.hasClients) {
    return;
  }
  final position = controller.position;
  if (position.axis != Axis.horizontal) {
    return;
  }
  if (!position.hasContentDimensions) {
    return;
  }
  if (!position.physics.shouldAcceptUserOffset(position)) {
    return;
  }
  final applied = axisDirectionIsReversed(position.axisDirection)
      ? -delta
      : delta;
  final target = (position.pixels + applied).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (applied == 0 || target == position.pixels) {
    return;
  }
  GestureBinding.instance.pointerSignalResolver.register(event, (
    PointerEvent resolved,
  ) {
    final scrollEvent = resolved as PointerScrollEvent;
    final resolvedDelta = horizontalMouseWheelDelta(scrollEvent);
    if (resolvedDelta == null || !controller.hasClients) {
      return;
    }
    final resolvedPosition = controller.position;
    final resolvedApplied =
        axisDirectionIsReversed(resolvedPosition.axisDirection)
        ? -resolvedDelta
        : resolvedDelta;
    if (resolvedApplied == 0) {
      return;
    }
    final resolvedTarget = (resolvedPosition.pixels + resolvedApplied).clamp(
      resolvedPosition.minScrollExtent,
      resolvedPosition.maxScrollExtent,
    );
    if (resolvedTarget == resolvedPosition.pixels) {
      return;
    }
    resolvedPosition.pointerScroll(resolvedApplied);
    scrollEvent.respond(allowPlatformDefault: false);
  });
}

/// Wheel delta to apply to a horizontal position, or null to leave the event
/// to Flutter (trackpad [dx], Shift+wheel, non-mouse devices).
@visibleForTesting
double? horizontalMouseWheelDelta(PointerScrollEvent event) {
  if (event.kind != PointerDeviceKind.mouse) {
    return null;
  }
  if (event.scrollDelta.dx != 0) {
    return null;
  }
  if (event.scrollDelta.dy == 0) {
    return null;
  }
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight)) {
    return null;
  }
  return event.scrollDelta.dy;
}
