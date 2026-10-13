import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tool_details.dart';
import 'package:flutter/material.dart';

/// One turn as the desktop draws it: the prompt, the work folded under
/// "Worked for", then what the agent answered.
class const AgentChatTurnView({
  super.key,
  required final AgentChatTurnSection section,
}) extends StatefulWidget {
  @override
  State<AgentChatTurnView> createState() => _AgentChatTurnViewState();
}

class _AgentChatTurnViewState extends State<AgentChatTurnView> {
  /// What the person chose; until then the section's default applies, so a
  /// turn folds its work away by itself when it finishes.
  bool? _expanded;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final expanded = _expanded ?? !section.collapsedByDefault;
    final planSteps = section.planSteps;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final prompt in section.prompts)
          AgentChatUserMessage(item: prompt),
        if (section.working || section.activity.isNotEmpty)
          _WorkedDivider(
            section: section,
            expanded: expanded,
            onToggle: section.canToggleActivity
                ? () => setState(() => _expanded = !expanded)
                : null,
          ),
        if (expanded)
          for (final row in section.activity)
            switch (row) {
              AgentChatActionGroupRow() => _ActionGroup(
                key: ValueKey<String>(row.key),
                row: row,
              ),
              AgentChatItemRow(:final item) => AgentChatItemRowView(
                key: ValueKey<String>(row.key),
                item: item,
              ),
            },
        if (planSteps != null) AgentChatPlanCard(item: planSteps),
        for (final answer in section.answers)
          switch (answer.type) {
            AgentChatItemType.userMessage => AgentChatUserMessage(item: answer),
            AgentChatItemType.assistantMessage => AgentChatAssistantMessage(
              item: answer,
            ),
            _ => AgentChatItemRowView(item: answer),
          },
        if (section.failed && !section.working) _TurnEnded(section: section),
      ],
    );
  }
}

class const _WorkedDivider({
  required final AgentChatTurnSection section,
  required final bool expanded,
  required final VoidCallback? onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final workedFor = section.workedFor;
    return InkWell(
      borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      onTap: onToggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Row(
          children: <Widget>[
            Flexible(
              child: section.working
                  ? AgentChatElapsedLabel(
                      startedAt: section.startedAt,
                      style: style,
                    )
                  : Text(
                      workedFor == null
                          ? 'Worked'
                          : 'Worked for ${agentChatDurationLabel(workedFor)}',
                      style: style,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
            ),
            if (onToggle != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space6),
              Icon(
                expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                size: AleraTokens.space16,
                color: AleraTokens.foregroundFaint,
              ),
            ],
            const SizedBox(width: AleraTokens.space12),
            const Expanded(child: Divider(color: AleraTokens.borderSubtle)),
          ],
        ),
      ),
    );
  }
}

/// The clock for live elapsed labels; a fixture can provide a stable time.
class const AgentChatElapsedClock({
  super.key,
  required final DateTime Function() now,
  required super.child,
}) extends InheritedWidget {
  static DateTime read(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AgentChatElapsedClock>()
          ?.now() ??
      DateTime.now();

  @override
  bool updateShouldNotify(AgentChatElapsedClock oldWidget) =>
      now != oldWidget.now;
}

/// "Working for 12s", ticking once a second while the app is in front.
class const AgentChatElapsedLabel({
  super.key,
  required final DateTime? startedAt,
  final TextStyle? style,
}) extends StatefulWidget {
  @override
  State<AgentChatElapsedLabel> createState() => _AgentChatElapsedLabelState();
}

class _AgentChatElapsedLabelState extends State<AgentChatElapsedLabel> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentChatElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _sync();
  }

  // TickerMode is off when the route is covered or the tab is not shown, so a
  // label nobody can see stops waking the app up.
  void _sync() {
    _timer?.cancel();
    _timer = widget.startedAt == null || !TickerMode.valuesOf(context).enabled
        ? null
        : Timer.periodic(AleraTokens.elapsedTimeTick, (_) {
            if (mounted) setState(() {});
          });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    final text = startedAt == null
        ? 'Working'
        : 'Working for ${agentChatDurationLabel(AgentChatElapsedClock.read(context).difference(startedAt))}';
    return AgentChatShimmerText(text: text, style: widget.style);
  }
}

/// A group of tool, command and file actions under one summary line.
class const _ActionGroup({
  super.key,
  required final AgentChatActionGroupRow row,
}) extends StatefulWidget {
  @override
  State<_ActionGroup> createState() => _ActionGroupState();
}

class _ActionGroupState extends State<_ActionGroup> {
  bool _expanded = false;

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
          _ActionRow(action: row.actions.single)
        else ...<Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: () => setState(() => _expanded = !_expanded),
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
                    _ActionRow(
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

class const _ActionRow({super.key, required final AgentChatWorkedAction action})
    extends StatefulWidget {
  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _expanded = false;

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
          onTap: item.hasDetails
              ? () => setState(() => _expanded = !_expanded)
              : null,
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

class const _TurnEnded({required final AgentChatTurnSection section})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final turn = section.turn;
    final message = turn?.errorMessage?.trim();
    final label = switch (turn?.status) {
      AgentChatTurnStatus.interrupted => 'Stopped',
      AgentChatTurnStatus.cancelled => 'Cancelled',
      _ => 'Turn failed',
    };
    return AgentChatNoticeCard(
      title: label,
      body: message == null || message.isEmpty ? null : message,
      tone: turn?.status == AgentChatTurnStatus.failed
          ? AleraTokens.error
          : AleraTokens.foregroundMuted,
      icon: turn?.status == AgentChatTurnStatus.failed
          ? AleraIcons.loadFailed
          : AleraIcons.stop,
    );
  }
}
