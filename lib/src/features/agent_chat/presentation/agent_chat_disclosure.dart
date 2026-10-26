import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// A tappable region that opens or closes something, announced to screen
/// readers as a button with its expanded state.
class const AgentChatDisclosure({
  super.key,
  required final bool expanded,
  required final VoidCallback? onToggle,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final onToggle = this.onToggle;
    return Semantics(
      button: onToggle != null,
      expanded: onToggle == null ? null : expanded,
      child: InkWell(
        onTap: onToggle,
        mouseCursor: onToggle == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space4,
          ),
          child: child,
        ),
      ),
    );
  }
}
