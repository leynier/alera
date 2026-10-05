import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Animates a child's background between [baseColor] and [hoverColor] on
/// pointer hover, with a tokenized radius and fade. Use for tappable rows and
/// cells that should reveal an elevated surface under the cursor.
///
/// With an [onTap] the container is a keyboard-reachable button: it joins the
/// focus traversal, activates on Enter or Space, and draws a focus ring while
/// keyboard navigation is active.
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
  static const Map<ShortcutActivator, Intent> _activationShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  bool _hovered = false;
  bool _focusHighlighted = false;

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTap?.call();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final radius = BorderRadius.circular(widget.borderRadius);
    Widget surface = MouseRegion(
      cursor: onTap != null ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovered || _focusHighlighted
                ? widget.hoverColor
                : widget.baseColor,
            borderRadius: radius,
          ),
          foregroundDecoration: _focusHighlighted
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: AleraTokens.focusRing,
                    width: AleraTokens.dividerExtent,
                  ),
                )
              : null,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    if (onTap == null) {
      return surface;
    }
    surface = FocusableActionDetector(
      shortcuts: _activationShortcuts,
      actions: _actions,
      onShowFocusHighlight: (value) {
        if (value != _focusHighlighted) {
          setState(() => _focusHighlighted = value);
        }
      },
      child: surface,
    );
    return Semantics(button: true, child: surface);
  }
}
