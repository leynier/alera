import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Stands in for the prompt of a turn the agent started by itself to keep
/// working toward its goal, as the desktop draws it.
class const AgentChatGoalContinuationMarker({super.key})
    extends StatelessWidget {
  static const String label = 'Continuing toward the goal';

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundFaint);
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
          child: Row(
            mainAxisAlignment: .center,
            children: <Widget>[
              const Icon(
                AleraIcons.goal,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
