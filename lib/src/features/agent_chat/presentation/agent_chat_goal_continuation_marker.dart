import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Stands in for the prompt of a turn the agent started by itself to keep
/// working toward its goal, so the turn does not read as an answer to
/// nothing.
///
/// With [background], it marks a turn the agent started once the
/// background work it waited on (its sub-agents) ended.
class const AgentChatGoalContinuationMarker({
  super.key,
  final bool background = false,
}) extends StatelessWidget {
  static const String label = 'Continuing toward the goal';
  static const String backgroundLabel = 'Continuing after background work';

  @override
  Widget build(BuildContext context) {
    final text = background ? backgroundLabel : label;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundFaint);
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                background ? AleraIcons.agent : AleraIcons.goal,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
