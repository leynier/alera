import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_phases.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

const int _initialRows = 6;
const int _pageRows = 12;

/// What the relationships panel can do with a row. Presentational, so the
/// panel previews and tests without a runtime.
final class const AgentChatRelationshipActions({
  required final ValueChanged<String> onOpenChat,
  final ValueChanged<String>? onOpenSubagent,
  final ValueChanged<String>? onStopSubagent,
  final VoidCallback? onMergeBack,
  final Set<String> stopping = const <String>{},
  final bool merging = false,
});

/// The chat's lineage, as T3 Code's relationships control lists it: the
/// parent and fork source pinned first, forks, then the agents still working
/// and, folded, the previous ones. Every row opens what it names; a running
/// sub-agent can be stopped and the fork source takes a merge-back.
class const AgentChatRelationshipsPanel({
  super.key,
  required final AgentChatRelationships relationships,
  required final AgentChatRelationshipActions actions,
}) extends StatefulWidget {
  @override
  State<AgentChatRelationshipsPanel> createState() =>
      _AgentChatRelationshipsPanelState();
}

class _AgentChatRelationshipsPanelState
    extends State<AgentChatRelationshipsPanel> {
  bool _previousExpanded = false;
  final Map<String, int> _visible = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relationships = widget.relationships;
    final previous = relationships.previous;
    final failed = relationships.failedPreviousCount;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space4),
            child: Text(
              relationships.heading,
              style: theme.textTheme.titleSmall,
            ),
          ),
          ..._group('related', relationships.related),
          ..._group('active', relationships.active),
          if (previous.isNotEmpty) ...<Widget>[
            InkWell(
              key: const ValueKey<String>('agent-chat-lineage-previous'),
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              onTap: () =>
                  setState(() => _previousExpanded = !_previousExpanded),
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space6),
                child: Row(
                  children: <Widget>[
                    const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        'Previous Agents',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (failed > 0)
                      Text(
                        '$failed failed',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                    if (!_previousExpanded) ...<Widget>[
                      const SizedBox(width: AleraTokens.space6),
                      Text(
                        '${previous.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                    ],
                    Icon(
                      _previousExpanded
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundFaint,
                    ),
                  ],
                ),
              ),
            ),
            if (_previousExpanded) ..._group('previous', previous),
          ],
        ],
      ),
    );
  }

  List<Widget> _group(String id, List<AgentChatRelation> relations) {
    if (relations.isEmpty) return const <Widget>[];
    final visible = _visible[id] ?? _initialRows;
    final hidden = relations.length - visible;
    return <Widget>[
      for (final relation in relations.take(visible))
        _RelationRow(
          key: ValueKey<String>('agent-chat-lineage-${relation.key}'),
          relation: relation,
          actions: widget.actions,
          mergeTarget: relation.kind == AgentChatRelationKind.forkSource,
        ),
      if (hidden > 0)
        TextButton.icon(
          key: ValueKey<String>('agent-chat-lineage-more-$id'),
          onPressed: () => setState(() => _visible[id] = visible + _pageRows),
          icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
          label: Text('Show ${hidden < _pageRows ? hidden : _pageRows} More'),
        ),
    ];
  }
}

class const _RelationRow({
  super.key,
  required final AgentChatRelation relation,
  required final AgentChatRelationshipActions actions,
  required final bool mergeTarget,
}) extends StatefulWidget {
  @override
  State<_RelationRow> createState() => _RelationRowState();
}

class _RelationRowState extends State<_RelationRow> {
  /// A workflow row unfolds its phases and members, as T3 Code's does.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final relation = widget.relation;
    final actions = widget.actions;
    final mergeTarget = widget.mergeTarget;
    final workflow = relation.workflow;
    final theme = Theme.of(context);
    final call = relation.call;
    final onOpen = call == null
        ? (relation.missing ? null : () => actions.onOpenChat(relation.chatId!))
        : switch (actions.onOpenSubagent) {
            final open? => () => open(call.id),
            null => null,
          };
    final stop = call != null && relation.active
        ? actions.onStopSubagent
        : null;
    final merge = mergeTarget ? actions.onMergeBack : null;
    final icon = switch (relation.kind) {
      AgentChatRelationKind.parentChat ||
      AgentChatRelationKind.forkSource => AleraIcons.back,
      AgentChatRelationKind.fork => AleraIcons.gitFork,
      AgentChatRelationKind.delegatedChat || AgentChatRelationKind.subagent =>
        workflow == null ? AleraIcons.agent : AleraIcons.workflow,
    };
    final row = Row(
      children: <Widget>[
        Expanded(
          child: Tooltip(
            message: relation.missing
                ? 'This related chat is unavailable'
                : 'Open ${relation.kindLabel.toLowerCase()}',
            child: InkWell(
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space6),
                child: Row(
                  children: <Widget>[
                    Icon(
                      icon,
                      size: AleraTokens.iconMd,
                      color: relation.failed
                          ? AleraTokens.error
                          : AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        relation.title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: relation.missing
                              ? AleraTokens.foregroundFaint
                              : AleraTokens.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Text(
                      '${relation.kindLabel} · ${relation.statusLabel}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: relation.failed
                            ? AleraTokens.error
                            : AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (merge != null)
          AleraIconButton(
            key: const ValueKey<String>('agent-chat-lineage-merge'),
            tooltip: 'Merge Back Into ${relation.title}',
            icon: AleraIcons.gitMerge,
            iconSize: AleraTokens.iconSm,
            minSize: AleraTokens.iconButtonSm,
            onPressed: actions.merging ? null : merge,
          ),
        if (stop != null)
          AleraIconButton(
            key: ValueKey<String>('agent-chat-lineage-stop-${call!.id}'),
            tooltip: workflow == null ? 'Stop Sub-agent' : 'Stop Workflow',
            icon: AleraIcons.square,
            iconSize: AleraTokens.iconSm,
            minSize: AleraTokens.iconButtonSm,
            iconColor: AleraTokens.error,
            onPressed: actions.stopping.contains(call.id)
                ? null
                : () => stop(call.id),
          ),
        if (workflow != null)
          AleraIconButton(
            key: ValueKey<String>('agent-chat-lineage-expand-${call!.id}'),
            tooltip: '${_expanded ? 'Collapse' : 'Expand'} ${relation.title}',
            icon: _expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
            iconSize: AleraTokens.iconSm,
            minSize: AleraTokens.iconButtonSm,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
      ],
    );
    if (workflow == null || !_expanded) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row,
        Padding(
          padding: const EdgeInsets.only(left: AleraTokens.space20),
          // A member opens with its workflow, where its answer is.
          child: AgentChatWorkflowPhases(
            group: workflow,
            onOpenMember: onOpen == null ? null : (_) => onOpen(),
          ),
        ),
      ],
    );
  }
}
