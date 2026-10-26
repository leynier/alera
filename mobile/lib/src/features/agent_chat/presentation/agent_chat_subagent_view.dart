import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_action_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:flutter/material.dart';

/// One activity row of a turn, a sub-agent's included.
Widget agentChatActivityRowView(AgentChatActivityRow row) => switch (row) {
  AgentChatActionGroupRow() => AgentChatActionGroupView(
    key: ValueKey<String>(row.key),
    row: row,
  ),
  AgentChatItemRow(:final item) => AgentChatItemRowView(
    key: ValueKey<String>(row.key),
    item: item,
  ),
  AgentChatSubagentRow() => AgentChatSubagentView(
    key: ValueKey<String>(row.key),
    row: row,
  ),
};

/// A provider-native sub-agent under the call that started it: its label and
/// state, and, opened, its own work along a thread line.
class const AgentChatSubagentView({
  super.key,
  required final AgentChatSubagentRow row,
}) extends StatefulWidget {
  @override
  State<AgentChatSubagentView> createState() => _AgentChatSubagentViewState();
}

class _AgentChatSubagentViewState extends State<AgentChatSubagentView> {
  // A failed sub-agent starts open, so the failure is in view.
  late bool _expanded = agentChatFoldExpanded(
    context,
    widget.row.key,
    fallback: widget.row.status == AgentChatSubagentStatus.failed,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(context, widget.row.key, expanded: _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final summary = row.summary?.trim() ?? '';
    final hasBody = row.rows.isNotEmpty || summary.isNotEmpty;
    final expanded = hasBody && _expanded;
    final failed = row.status == AgentChatSubagentStatus.failed;
    final color = failed ? AleraTokens.error : AleraTokens.foregroundMuted;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final label = 'Sub-agent: ${row.label}';
    final state = row.childCount == 0
        ? row.status.label
        : '${row.status.label} · ${row.childCount} '
              '${row.childCount == 1 ? 'step' : 'steps'}';
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Semantics(
          button: hasBody,
          expanded: hasBody ? expanded : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: hasBody ? _toggle : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    AleraIcons.agent,
                    size: AleraTokens.space16,
                    color: color,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: row.streaming
                        ? AgentChatShimmerText(text: label, style: style)
                        : Text(label, style: style, overflow: .ellipsis),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    state,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: failed
                          ? AleraTokens.error
                          : AleraTokens.foregroundFaint,
                    ),
                  ),
                  if (hasBody)
                    Icon(
                      expanded
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.space16,
                      color: AleraTokens.foregroundFaint,
                    ),
                  AgentChatSubagentRowActions(
                    call: row.call,
                    running: row.streaming,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            margin: const EdgeInsets.only(left: AleraTokens.space8),
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                for (final child in row.rows) agentChatActivityRowView(child),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
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
