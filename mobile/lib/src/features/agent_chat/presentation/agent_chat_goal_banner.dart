import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// The goal the agent keeps working toward, as the desktop shows it: its
/// state and spend, the objective, and the ways to resume or clear it. Both
/// actions are ordinary `/goal` messages, so the host decides whether a
/// running turn stops for them.
class const AgentChatGoalBanner({
  super.key,
  required final AgentChatGoal goal,

  /// The chat runs a turn right now.
  required final bool busy,

  /// The chat can take a message.
  required final bool enabled,
  required final VoidCallback onResume,
  required final VoidCallback onClear,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = AgentChatGoalPresentation.of(goal, working: busy);
    return DecoratedBox(
      key: const ValueKey<String>('agent-chat-goal'),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space12,
          AleraTokens.space8,
          AleraTokens.space4,
          0,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: AleraTokens.space2),
                  child: Icon(
                    AleraIcons.goal,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      Text(
                        presentation.heading,
                        key: const ValueKey<String>('agent-chat-goal-title'),
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: AleraTokens.space2),
                      Text(
                        presentation.objective,
                        key: const ValueKey<String>(
                          'agent-chat-goal-objective',
                        ),
                        maxLines: 3,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
              ],
            ),
            Wrap(
              alignment: .end,
              spacing: AleraTokens.space4,
              children: <Widget>[
                // Clear stops goal work; Resume would stop unrelated work, so
                // it waits for the turn to end.
                if (presentation.canResume && !busy)
                  TextButton(
                    key: const ValueKey<String>('agent-chat-goal-resume'),
                    onPressed: enabled ? onResume : null,
                    child: const Text('Resume'),
                  ),
                TextButton(
                  key: const ValueKey<String>('agent-chat-goal-clear'),
                  onPressed: enabled ? onClear : null,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
