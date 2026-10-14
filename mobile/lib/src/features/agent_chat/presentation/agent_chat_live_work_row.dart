import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_action_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:flutter/material.dart';

/// What a running turn shows for its work: narration inline, then one row
/// for what the agent is doing now and the first sentence of its latest
/// reasoning. Everything earlier sits behind the "N earlier actions"
/// disclosure, so a long turn costs one row rather than one per action.
class const AgentChatLiveWorkRow({
  super.key,
  required final AgentChatLiveWork work,
  required final bool expanded,
  required final VoidCallback? onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final current = work.current;
    // Earlier reasoning or notices alone still open the disclosure.
    final earlier =
        work.earlierLabel ?? (work.hiddenCount > 0 ? 'Show Details' : null);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final item in work.narration)
          AgentChatItemRowView(key: ValueKey<String>(item.id), item: item),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                current == null
                    ? AleraIcons.sparkles
                    : agentChatActionIcon(current.kind),
                size: AleraTokens.space16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    AgentChatShimmerText(text: work.label, style: style),
                    if (work.reasoning case final reasoning?)
                      Text(
                        reasoning,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (earlier != null && onToggle != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              expanded: expanded,
              child: TextButton.icon(
                onPressed: onToggle,
                icon: Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: AleraTokens.space16,
                ),
                label: Text(earlier),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Changed Files (N)" under a settled turn, opening to the paths it touched
/// in the order they were last changed.
class const AgentChatChangedFiles({
  super.key,
  required final String turnId,
  required final List<AgentChatFileChange> changes,
}) extends StatefulWidget {
  @override
  State<AgentChatChangedFiles> createState() => _AgentChatChangedFilesState();
}

class _AgentChatChangedFilesState extends State<AgentChatChangedFiles> {
  late bool _expanded = agentChatFoldExpanded(
    context,
    agentChatChangedFilesFoldKey(widget.turnId),
    fallback: false,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(
      context,
      agentChatChangedFilesFoldKey(widget.turnId),
      expanded: _expanded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final viewChanges = AgentChatHistoryActions.maybeOf(context)?.onViewChanges;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    AleraIcons.edit,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      agentChatChangedFilesLabel(widget.changes.length),
                      style: style,
                    ),
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
        ),
        if (_expanded && viewChanges != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space16),
              child: TextButton.icon(
                onPressed: () => viewChanges(widget.turnId),
                icon: const Icon(AleraIcons.gitCompare),
                label: const Text('View Changes'),
              ),
            ),
          ),
        if (_expanded)
          for (final change in widget.changes)
            Padding(
              key: ValueKey<String>('change-${change.path}'),
              padding: const EdgeInsets.only(
                left: AleraTokens.space24,
                bottom: AleraTokens.space4,
              ),
              child: Row(
                children: <Widget>[
                  AleraFileIcon(
                    pathOrName: change.path,
                    kind: AleraFileIconKind.file,
                    size: AleraTokens.iconSm,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      change.movePath == null
                          ? change.path
                          : '${change.path} → ${change.movePath}',
                      style: AleraTokens.monoStyle,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                  Text(
                    switch (change.kind) {
                      AgentChatFileChangeKind.add => 'Added',
                      AgentChatFileChangeKind.delete => 'Deleted',
                      AgentChatFileChangeKind.rename => 'Renamed',
                      AgentChatFileChangeKind.update => 'Edited',
                    },
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AleraTokens.foregroundFaint),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
