import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Places a [showMenu] popup just below [anchor] (global bounds). The menu
/// grows away from the nearer screen edge, so an anchor on the right keeps
/// the menu aligned to its right edge instead of spilling off screen.
RelativeRect aleraMenuBelow(BuildContext context, Rect anchor) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final size = overlay.size;
  final top = anchor.bottom + AleraTokens.space4;
  return RelativeRect.fromLTRB(
    anchor.left,
    top,
    size.width - anchor.right,
    (size.height - top).clamp(0.0, double.infinity),
  );
}
