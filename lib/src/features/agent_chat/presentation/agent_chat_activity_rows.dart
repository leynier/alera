import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_disclosure.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_item_details.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_row.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A row under "Worked for": a folded group of actions or a single item.
class const AgentChatActivityRowView({
  super.key,
  required final AgentChatActivityRow row,
  required final AgentChatExpansion expansion,
  required final AgentChatTimelineActions actions,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (row) {
      AgentChatActionGroupRow(:final actions) when actions.length == 1 =>
        _ActionRow(
          action: actions.single,
          expansion: expansion,
          onOpenFile: this.actions.onOpenFile,
        ),
      final AgentChatActionGroupRow group => _ActionGroup(
        group: group,
        expansion: expansion,
        onOpenFile: actions.onOpenFile,
      ),
      AgentChatItemRow(:final item) => AgentChatItemRowView(
        item: item,
        expansion: expansion,
        actions: actions,
        workspacePath: workspacePath,
      ),
      final AgentChatSubagentRow subagent => AgentChatSubagentRowView(
        row: subagent,
        expansion: expansion,
        actions: actions,
        workspacePath: workspacePath,
      ),
    };
  }
}

/// A single item that is not a grouped action: reasoning, narration, notices,
/// errors, compaction, and anything the runtime could not classify.
class const AgentChatItemRowView({
  super.key,
  required final AgentChatItem item,
  required final AgentChatExpansion expansion,
  required final AgentChatTimelineActions actions,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (item.type) {
      AgentChatItemType.reasoning => _ReasoningRow(
        item: item,
        expansion: expansion,
      ),
      AgentChatItemType.assistantMessage => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: AleraTokens.space2,
        ),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
          child: item.isPartialContinuation
              ? AgentChatPartialText(text: item.text, muted: true)
              : AgentChatMarkdown(
                  data: item.text,
                  onOpenLink: actions.onOpenLink,
                  muted: true,
                ),
        ),
      ),
      AgentChatItemType.userMessage => AgentChatUserMessageView(
        chatId: actions.chatId,
        item: item,
        workspacePath: workspacePath,
        onOpenFile: actions.onOpenFile,
        steering: true,
      ),
      AgentChatItemType.error => AgentChatNoticeRow(
        icon: AleraIcons.warning,
        message: _message(item, fallback: 'The agent reported an error.'),
        tone: AgentChatNoticeTone.error,
      ),
      AgentChatItemType.notice => AgentChatNoticeRow(
        icon: AleraIcons.info,
        message: _message(item, fallback: 'Notice'),
      ),
      AgentChatItemType.contextCompaction => AgentChatNoticeRow(
        icon: AleraIcons.contextCompact,
        message: item.isFailed
            ? 'Compaction failed'
            : item.isInProgress
            ? 'Compacting context'
            : 'Compacted context',
        tone: item.isFailed
            ? AgentChatNoticeTone.error
            : AgentChatNoticeTone.muted,
        shimmer: item.isInProgress,
      ),
      _ => _ActionRow(
        action: AgentChatWorkedAction(
          item: item,
          kind: AgentChatWorkedActionKind.tool,
          label: item.title ?? item.toolName ?? 'Agent activity',
        ),
        expansion: expansion,
        onOpenFile: actions.onOpenFile,
      ),
    };
  }

  static String _message(AgentChatItem item, {required String fallback}) {
    for (final candidate in <String?>[item.detail, item.text, item.title]) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate;
    }
    return fallback;
  }
}

enum AgentChatNoticeTone { muted, error }

class const AgentChatNoticeRow({
  super.key,
  required final IconData icon,
  required final String message,
  final AgentChatNoticeTone tone = AgentChatNoticeTone.muted,
  final bool shimmer = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = tone == AgentChatNoticeTone.error
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space2),
            child: Icon(icon, size: AleraTokens.iconSm, color: color),
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: shimmer
                ? AleraShimmerText(text: message, style: style)
                : Text(message, style: style),
          ),
        ],
      ),
    );
  }
}

class const _ReasoningRow({
  required final AgentChatItem item,
  required final AgentChatExpansion expansion,
}) extends StatefulWidget {
  @override
  State<_ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<_ReasoningRow> {
  String get _key => agentChatReasoningFoldKey(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final text = item.reasoningText.trim().isNotEmpty
        ? item.reasoningText
        : item.text;
    final expanded = widget.expansion.isExpanded(_key, byDefault: false);
    final hasText = text.trim().isNotEmpty;
    final label = agentChatReasoningLabel(item);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AgentChatDisclosure(
          key: ValueKey<String>('agent-chat-reasoning-${item.id}'),
          expanded: expanded,
          onToggle: hasText
              ? () => setState(
                  () => widget.expansion.set(_key, expanded: !expanded),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                AleraIcons.ai,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              if (item.isInProgress)
                AleraShimmerText(text: label, style: style)
              else
                Text(label, style: style),
              if (hasText) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ],
          ),
        ),
        if (expanded && hasText)
          Container(
            margin: const EdgeInsets.only(
              left: AleraTokens.space12,
              top: AleraTokens.space2,
              bottom: AleraTokens.space4,
            ),
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AleraTokens.borderSubtle,
                  width: AleraTokens.strokeSm,
                ),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: style,
              child: item.isPartialContinuation
                  ? AgentChatPartialText(text: text, muted: true)
                  : AgentChatMarkdown(data: text, muted: true),
            ),
          ),
        if (item.isPartialContinuation && !expanded)
          const AgentChatPartialMessageNote(),
      ],
    );
  }
}

class const _ActionGroup({
  required final AgentChatActionGroupRow group,
  required final AgentChatExpansion expansion,
  required final ValueChanged<String> onOpenFile,
}) extends StatefulWidget {
  @override
  State<_ActionGroup> createState() => _ActionGroupState();
}

class _ActionGroupState extends State<_ActionGroup> {
  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final key = agentChatActionGroupFoldKey(group);
    final expanded = widget.expansion.isExpanded(key, byDefault: false);
    final first = group.actions.first;
    final icon =
        group.actions.any(
          (action) => action.kind == AgentChatWorkedActionKind.edit,
        )
        ? AleraIcons.edit
        : agentChatWorkedActionIcon(first.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _RowHeader(
          key: ValueKey<String>('agent-chat-action-group-${first.item.id}'),
          icon: icon,
          label: group.summary,
          failed: group.failed,
          streaming: group.streaming,
          expandable: true,
          expanded: expanded,
          onTap: () =>
              setState(() => widget.expansion.set(key, expanded: !expanded)),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final action in group.actions)
                  _ActionRow(
                    key: ValueKey<String>(
                      'agent-chat-action-${action.item.id}',
                    ),
                    action: action,
                    expansion: widget.expansion,
                    onOpenFile: widget.onOpenFile,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class const _ActionRow({
  super.key,
  required final AgentChatWorkedAction action,
  required final AgentChatExpansion expansion,
  required final ValueChanged<String> onOpenFile,
}) extends StatefulWidget {
  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  String get _key => agentChatActionFoldKey(widget.action.item.id);

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final item = action.item;
    final hasDetails = item.hasDetails;
    final expanded =
        hasDetails && widget.expansion.isExpanded(_key, byDefault: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _RowHeader(
          key: ValueKey<String>('agent-chat-action-row-${item.id}'),
          icon: agentChatWorkedActionIcon(action.kind),
          label: action.label,
          failed: item.isFailed,
          streaming: item.isInProgress,
          expandable: hasDetails,
          expanded: expanded,
          onTap: hasDetails
              ? () => setState(
                  () => widget.expansion.set(_key, expanded: !expanded),
                )
              : null,
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(
              left: AleraTokens.space24,
              top: AleraTokens.space2,
              bottom: AleraTokens.space6,
            ),
            padding: const EdgeInsets.all(AleraTokens.space8),
            decoration: BoxDecoration(
              color: AleraTokens.surface,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              border: Border.all(color: AleraTokens.borderSubtle),
            ),
            child: AgentChatItemDetails(
              item: item,
              onOpenFile: widget.onOpenFile,
            ),
          ),
      ],
    );
  }
}

class const _RowHeader({
  super.key,
  required final IconData icon,
  required final String label,
  required final bool failed,
  required final bool streaming,
  required final bool expandable,
  required final bool expanded,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = failed ? AleraTokens.error : AleraTokens.foregroundMuted;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return AgentChatDisclosure(
      expanded: expanded,
      onToggle: expandable ? onTap : null,
      child: Row(
        children: <Widget>[
          Icon(icon, size: AleraTokens.iconMd, color: color),
          const SizedBox(width: AleraTokens.space8),
          Flexible(
            child: streaming
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
          if (expandable && !streaming) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            Icon(
              expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
              size: AleraTokens.iconMd,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ],
      ),
    );
  }
}

IconData agentChatWorkedActionIcon(AgentChatWorkedActionKind kind) =>
    switch (kind) {
      AgentChatWorkedActionKind.review => AleraIcons.review,
      AgentChatWorkedActionKind.edit => AleraIcons.edit,
      AgentChatWorkedActionKind.read => AleraIcons.read,
      AgentChatWorkedActionKind.viewImage => AleraIcons.viewImage,
      AgentChatWorkedActionKind.listFiles => AleraIcons.file,
      AgentChatWorkedActionKind.search => AleraIcons.search,
      AgentChatWorkedActionKind.webSearch => AleraIcons.public,
      AgentChatWorkedActionKind.delegate => AleraIcons.agent,
      AgentChatWorkedActionKind.tool => AleraIcons.devTools,
      AgentChatWorkedActionKind.ran => AleraIcons.terminal,
    };
