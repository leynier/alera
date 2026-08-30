import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Grouped container that stacks [children] separated by hairline dividers,
/// on an emphasized neutral surface. Used for settings groups and any list of
/// related rows that should read as one card.
///
/// Defaults to the elevated [AleraTokens.surfaceVariant] background and the
/// subtle border. Callers can pass [backgroundColor] / [borderColor] for the
/// flatter "result panel" variant used inside search popovers.
class const AleraPanel({
  super.key,
  required final List<Widget> children,
  final Color? backgroundColor,
  final Color? borderColor,
  final double? borderRadius,
  final Clip clipBehavior = Clip.none,
  final double? maxHeight,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? AleraTokens.radiusLg);
    return Container(
      clipBehavior: clipBehavior,
      constraints: maxHeight == null
          ? null
          : BoxConstraints(maxHeight: maxHeight!),
      decoration: BoxDecoration(
        color: backgroundColor ?? AleraTokens.surfaceVariant,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(height: 1, color: AleraTokens.borderSubtle),
            children[i],
          ],
        ],
      ),
    );
  }
}
