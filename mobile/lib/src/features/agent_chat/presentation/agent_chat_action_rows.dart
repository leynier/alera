import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tool_details.dart';
import 'package:flutter/material.dart';

/// A group of tool, command and file actions under one summary line.
class const AgentChatActionGroupView({
  super.key,
  required final AgentChatActionGroupRow row,
}) extends StatefulWidget {
  @override
  State<AgentChatActionGroupView> createState() =>
      _AgentChatActionGroupViewState();
}

class _AgentChatActionGroupViewState extends State<AgentChatActionGroupView> {
  // A group holding a failed action starts open, so the failure is in view.
  late bool _expanded = agentChatFoldExpanded(
    context,
    agentChatActionGroupFoldKey(widget.row),
    fallback: widget.row.failed,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(
      context,
      agentChatActionGroupFoldKey(widget.row),
      expanded: _expanded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final color = row.failed ? AleraTokens.error : AleraTokens.foregroundMuted;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    final single = row.actions.length == 1;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (single)
          AgentChatActionRowView(action: row.actions.single)
        else ...<Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    AleraIcons.tool,
                    size: AleraTokens.space16,
                    color: color,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: row.streaming
                        ? AgentChatShimmerText(text: row.summary, style: style)
                        : Text(row.summary, style: style, overflow: .ellipsis),
                  ),
                  Icon(
                    _expanded
                        ? AleraIcons.chevronDown
                        : AleraIcons.chevronRight,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space12),
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  for (final action in row.actions)
                    AgentChatActionRowView(
                      key: ValueKey<String>(action.item.id),
                      action: action,
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One action; tapping it opens its command, output or diff.
class const AgentChatActionRowView({
  super.key,
  required final AgentChatWorkedAction action,
}) extends StatefulWidget {
  @override
  State<AgentChatActionRowView> createState() => _AgentChatActionRowViewState();
}

class _AgentChatActionRowViewState extends State<AgentChatActionRowView> {
  late bool _expanded = agentChatFoldExpanded(
    context,
    agentChatActionFoldKey(widget.action.item.id),
    fallback: false,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(
      context,
      agentChatActionFoldKey(widget.action.item.id),
      expanded: _expanded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final item = action.item;
    final color = item.isFailed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          onTap: item.hasDetails ? _toggle : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AleraTokens.minTapTarget,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  agentChatActionIcon(action.kind),
                  size: AleraTokens.space16,
                  color: color,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: item.isInProgress
                      ? AgentChatShimmerText(text: action.label, style: style)
                      : Text(
                          action.label,
                          style: style,
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AleraTokens.space24,
              bottom: AleraTokens.space8,
            ),
            child: AgentChatToolDetails(item: item),
          ),
      ],
    );
  }
}

IconData agentChatActionIcon(AgentChatWorkedActionKind kind) => switch (kind) {
  AgentChatWorkedActionKind.review => AleraIcons.review,
  AgentChatWorkedActionKind.edit => AleraIcons.edit,
  AgentChatWorkedActionKind.read => AleraIcons.file,
  AgentChatWorkedActionKind.viewImage => AleraIcons.viewImage,
  AgentChatWorkedActionKind.listFiles => AleraIcons.listView,
  AgentChatWorkedActionKind.search => AleraIcons.search,
  AgentChatWorkedActionKind.webSearch => AleraIcons.public,
  AgentChatWorkedActionKind.delegate => AleraIcons.agent,
  AgentChatWorkedActionKind.tool => AleraIcons.tool,
  AgentChatWorkedActionKind.ran => AleraIcons.terminal,
};
