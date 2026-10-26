import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_disclosure.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_scope.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A provider-native sub-agent under the call that started it: its label and
/// state, and, opened, its own work along a thread line.
class const AgentChatSubagentRowView({
  super.key,
  required final AgentChatSubagentRow row,
  required final AgentChatExpansion expansion,
  required final AgentChatTimelineActions actions,
  required final String workspacePath,
}) extends StatefulWidget {
  @override
  State<AgentChatSubagentRowView> createState() =>
      _AgentChatSubagentRowViewState();
}

class _AgentChatSubagentRowViewState extends State<AgentChatSubagentRowView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final key = row.key;
    final summary = row.summary?.trim() ?? '';
    final hasBody = row.rows.isNotEmpty || summary.isNotEmpty;
    final expanded =
        hasBody && widget.expansion.isExpanded(key, byDefault: false);
    final failed = row.status == AgentChatSubagentStatus.failed;
    final color = failed ? AleraTokens.error : AleraTokens.foregroundMuted;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final label = 'Sub-agent: ${row.label}';
    final scope = AgentChatSubagentScope.maybeOf(context);
    final onOpen = scope?.onOpen;
    final onStop = row.streaming ? scope?.onStop : null;
    final stopping = scope?.stopping.contains(row.call.id) ?? false;
    return Column(
      key: ValueKey<String>('agent-chat-subagent-${row.call.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AgentChatDisclosure(
          expanded: expanded,
          onToggle: hasBody
              ? () => setState(
                  () => widget.expansion.set(key, expanded: !expanded),
                )
              : null,
          child: Row(
            children: <Widget>[
              Icon(AleraIcons.agent, size: AleraTokens.iconMd, color: color),
              const SizedBox(width: AleraTokens.space8),
              Flexible(
                child: row.streaming
                    ? AleraShimmerText(
                        text: label,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        label,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(
                row.childCount == 0
                    ? row.status.label
                    : '${row.status.label} · ${row.childCount} '
                          '${row.childCount == 1 ? 'step' : 'steps'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: failed
                      ? AleraTokens.error
                      : AleraTokens.foregroundFaint,
                ),
              ),
              if (hasBody) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
              if (onStop != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  key: ValueKey<String>(
                    'agent-chat-subagent-stop-${row.call.id}',
                  ),
                  tooltip: 'Stop Sub-agent',
                  icon: AleraIcons.square,
                  iconSize: AleraTokens.iconSm,
                  minSize: AleraTokens.iconButtonXs,
                  iconColor: AleraTokens.error,
                  onPressed: stopping ? null : () => onStop(row.call.id),
                ),
              ],
              if (onOpen != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  key: ValueKey<String>(
                    'agent-chat-subagent-open-${row.call.id}',
                  ),
                  tooltip: 'Open Sub-agent',
                  icon: AleraIcons.forward,
                  iconSize: AleraTokens.iconSm,
                  minSize: AleraTokens.iconButtonXs,
                  onPressed: () => onOpen(row.call.id),
                ),
              ],
            ],
          ),
        ),
        if (expanded)
          Container(
            margin: const EdgeInsets.only(left: AleraTokens.space12),
            padding: const EdgeInsets.only(left: AleraTokens.space6),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AleraTokens.borderSubtle,
                  width: AleraTokens.dividerExtent,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final child in row.rows)
                  AgentChatActivityRowView(
                    key: ValueKey<String>(child.key),
                    row: child,
                    expansion: widget.expansion,
                    actions: widget.actions,
                    workspacePath: widget.workspacePath,
                  ),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space6,
                      vertical: AleraTokens.space4,
                    ),
                    child: SelectableText(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
