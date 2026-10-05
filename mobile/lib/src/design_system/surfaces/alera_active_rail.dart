import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Marks the selected item of a vertical list with a short accent rail at the
/// leading edge, drawn over [child] so selecting a row never shifts its
/// layout. Pair it with [selectedColor] as the row's own background.
///
/// Vertical lists only: horizontal tab chips mark the active chip with
/// [selectedColor] and accent text or icon instead of a rail. Mirrors the
/// desktop widget of the same name.
class const AleraActiveRail({
  super.key,
  required final bool active,
  required final Widget child,
}) extends StatelessWidget {
  /// Background of a selected row. A translucent accent rather than
  /// surfaceElevated, which is nearly the same gray as the sidebar and panel
  /// chrome and left the selection hard to see.
  static const Color selectedColor = AleraTokens.accentSubtle;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return child;
    }
    return Stack(
      fit: .passthrough,
      children: <Widget>[
        child,
        const PositionedDirectional(
          start: 0,
          top: AleraTokens.space6,
          bottom: AleraTokens.space6,
          width: AleraTokens.activeRailWidth,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey<String>('alera-active-rail'),
              decoration: BoxDecoration(
                color: AleraTokens.accent,
                borderRadius: BorderRadius.all(.circular(AleraTokens.radiusXs)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
