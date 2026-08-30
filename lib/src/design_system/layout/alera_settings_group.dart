import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';

/// Titled group of setting rows: a heading with an optional description above
/// an [AleraPanel] that stacks [children] separated by hairline dividers.
class const AleraSettingsGroup({
  super.key,
  required final String title,
  final String? description,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w600,
                ),
              ),
              if (description != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space4),
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        AleraPanel(children: children),
      ],
    );
  }
}
