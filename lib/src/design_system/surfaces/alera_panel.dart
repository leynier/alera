import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Grouped container that stacks [children] separated by hairline dividers,
/// on an emphasized neutral surface. Used for settings groups and any list of
/// related rows that should read as one card.
class AleraPanel extends StatelessWidget {
  const AleraPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
