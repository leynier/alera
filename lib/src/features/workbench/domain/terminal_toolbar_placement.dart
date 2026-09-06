import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';

extension TerminalToolbarCornerLayout on TerminalToolbarCorner {
  bool get isTop =>
      this == TerminalToolbarCorner.topLeft ||
      this == TerminalToolbarCorner.topRight;

  bool get isLeft =>
      this == TerminalToolbarCorner.topLeft ||
      this == TerminalToolbarCorner.bottomLeft;

  bool get isBottom => !isTop;

  bool get isRight => !isLeft;
}

class const TerminalToolbarAnchor({
  final double? top,
  final double? left,
  final double? right,
  final double? bottom,
}) {
  @override
  bool operator ==(Object other) {
    return other is TerminalToolbarAnchor &&
        other.top == top &&
        other.left == left &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(top, left, right, bottom);

  static TerminalToolbarAnchor forCorner(
    TerminalToolbarCorner corner, {
    double inset = AleraTokens.space4,
  }) {
    return TerminalToolbarAnchor(
      top: corner.isTop ? inset : null,
      bottom: corner.isBottom ? inset : null,
      left: corner.isLeft ? inset : null,
      right: corner.isRight ? inset : null,
    );
  }
}

({double left, double top}) terminalToolbarOffset({
  required TerminalToolbarCorner corner,
  required double viewportWidth,
  required double viewportHeight,
  required double toolbarWidth,
  required double toolbarHeight,
  double inset = AleraTokens.space4,
}) {
  return (
    left: corner.isLeft ? inset : viewportWidth - toolbarWidth - inset,
    top: corner.isTop ? inset : viewportHeight - toolbarHeight - inset,
  );
}

double clampTerminalToolbarLeft({
  required double left,
  required double viewportWidth,
  required double toolbarWidth,
  double inset = AleraTokens.space4,
}) {
  final maxLeft = viewportWidth - toolbarWidth - inset;
  if (maxLeft <= inset) {
    return inset;
  }
  return left.clamp(inset, maxLeft);
}

double clampTerminalToolbarTop({
  required double top,
  required double viewportHeight,
  required double toolbarHeight,
  double inset = AleraTokens.space4,
}) {
  final maxTop = viewportHeight - toolbarHeight - inset;
  if (maxTop <= inset) {
    return inset;
  }
  return top.clamp(inset, maxTop);
}

TerminalToolbarCorner nearestTerminalToolbarCorner({
  required double centerX,
  required double centerY,
  required double viewportWidth,
  required double viewportHeight,
}) {
  final left = centerX <= viewportWidth / 2;
  final top = centerY <= viewportHeight / 2;
  if (top) {
    return left
        ? TerminalToolbarCorner.topLeft
        : TerminalToolbarCorner.topRight;
  }
  return left
      ? TerminalToolbarCorner.bottomLeft
      : TerminalToolbarCorner.bottomRight;
}

class const TerminalSearchOverlayLayout({
  required final double left,
  required final double right,
  required final bool alignLeft,
});

TerminalSearchOverlayLayout terminalSearchOverlayLayout({
  required TerminalToolbarCorner toolbarCorner,
  required int toolbarButtonCount,
}) {
  final toolbarInset =
      AleraTokens.space48 * toolbarButtonCount + AleraTokens.space4;
  if (toolbarCorner == TerminalToolbarCorner.topLeft) {
    return TerminalSearchOverlayLayout(
      left: toolbarInset,
      right: AleraTokens.space16,
      alignLeft: true,
    );
  }
  if (toolbarCorner == TerminalToolbarCorner.topRight) {
    return TerminalSearchOverlayLayout(
      left: AleraTokens.space16,
      right: toolbarInset,
      alignLeft: false,
    );
  }
  return const TerminalSearchOverlayLayout(
    left: AleraTokens.space16,
    right: AleraTokens.space16,
    alignLeft: false,
  );
}

int terminalToolbarButtonCount({required bool supportsPulse}) {
  // Move handle, composer, and refresh are always present.
  return 3 + (supportsPulse ? 1 : 0);
}
