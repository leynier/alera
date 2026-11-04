import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The goal the agent keeps working toward, above the composer: its state
/// and spend, the objective, and the ways to resume or clear it. Both
/// actions are ordinary `/goal` messages, so the runtime decides whether a
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
    ButtonStyle buttonStyle({Color? color}) => TextButton.styleFrom(
      minimumSize: const Size(0, AleraTokens.iconButtonSm),
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: color,
      textStyle: theme.textTheme.labelSmall,
    );
    return Container(
      key: const ValueKey<String>('agent-chat-goal'),
      constraints: const BoxConstraints(
        maxWidth: AleraTokens.agentChatDockMaxWidth,
      ),
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space4,
        AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.space2),
            child: Icon(
              AleraIcons.goal,
              size: AleraTokens.iconMd,
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  presentation.heading,
                  key: const ValueKey<String>('agent-chat-goal-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: AleraTokens.space2),
                Tooltip(
                  message: presentation.objective,
                  child: Text(
                    presentation.objective,
                    key: const ValueKey<String>('agent-chat-goal-objective'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          // Clear stops goal work; Resume would stop unrelated work, so it
          // waits for the turn to end.
          if (presentation.canResume && !busy)
            TextButton(
              key: const ValueKey<String>('agent-chat-goal-resume'),
              style: buttonStyle(),
              onPressed: enabled ? onResume : null,
              child: const Text('Resume'),
            ),
          TextButton(
            key: const ValueKey<String>('agent-chat-goal-clear'),
            style: buttonStyle(color: AleraTokens.foregroundMuted),
            onPressed: enabled ? onClear : null,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
