import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_goal_continuation_marker.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_handoff_divider.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_live_work_row.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_view.dart';
import 'package:flutter/material.dart';

/// One turn as the desktop draws it. While it runs: the prompt, "Working
/// for", one live row for the current action and what came before behind a
/// disclosure. Once it succeeds: the work folded under "Worked for", the
/// answer, and the files it changed. A turn that failed, stopped or was cut
/// short stays open, so the failing action is in view. A steering prompt
/// sits between the work it split, and the work after it folds under its own
/// "Continued for" divider.
class const AgentChatTurnView({
  super.key,
  required final AgentChatTurnSection section,
}) extends StatefulWidget {
  @override
  State<AgentChatTurnView> createState() => _AgentChatTurnViewState();
}

class _AgentChatTurnViewState extends State<AgentChatTurnView> {
  /// What the person chose, remembered per chat; until then the segment's
  /// default applies, so its work folds away by itself when it succeeds and
  /// opens up when it fails.
  bool _expanded(AgentChatTurnSegment segment) => agentChatFoldExpanded(
    context,
    segment.foldKey,
    fallback: !segment.collapsedByDefault,
  );

  void _toggle(AgentChatTurnSegment segment) => setState(
    () => agentChatRememberFold(
      context,
      segment.foldKey,
      expanded: !_expanded(segment),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final settled = !section.working;
    final handoff = section.handoff?.handoff;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (handoff != null) AgentChatHandoffDivider(handoff: handoff),
        if (section.goalContinuation) const AgentChatGoalContinuationMarker(),
        for (final prompt in section.prompts)
          AgentChatUserMessage(item: prompt),
        for (final segment in section.segments) ..._segment(segment),
        if (settled && section.changedFiles.isNotEmpty)
          AgentChatChangedFiles(
            turnId: section.turnId,
            changes: section.changedFiles,
          ),
        if (section.failed && settled) _TurnEnded(section: section),
      ],
    );
  }

  /// A segment's steers, its divider, its work and its answers. The first
  /// segment's divider is the turn header, with the whole turn's time.
  List<Widget> _segment(AgentChatTurnSegment segment) {
    final section = widget.section;
    final expanded = _expanded(segment);
    final live = segment.liveWork;
    final planSteps = segment == section.segments.last
        ? section.planSteps
        : null;
    void toggle() => _toggle(segment);
    final first = segment.index == 0;
    final showDivider = first
        ? section.working || section.activity.isNotEmpty
        : segment.live || segment.activity.isNotEmpty;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final segmentLabel = agentChatTurnSegmentHeaderLabel(segment);
    return <Widget>[
      for (final steer in segment.steers) AgentChatUserMessage(item: steer),
      if (showDivider)
        _FoldDivider(
          expanded: expanded,
          onToggle: segment.canToggleActivity && !segment.live ? toggle : null,
          label: first
              ? AgentChatTurnHeaderText(section: section, style: style)
              : segment.live
              ? AgentChatShimmerText(text: segmentLabel, style: style)
              : Text(
                  segmentLabel,
                  style: style,
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
        ),
      if (live != null && !expanded)
        AgentChatLiveWorkRow(
          work: live,
          expanded: false,
          onToggle: segment.canToggleActivity ? toggle : null,
        )
      else if (expanded) ...<Widget>[
        for (final row in segment.activity) agentChatActivityRowView(row),
        if (live != null)
          AgentChatLiveWorkRow(work: live, expanded: true, onToggle: toggle),
      ],
      if (planSteps != null) AgentChatPlanCard(item: planSteps),
      for (final answer in segment.answers)
        switch (answer.type) {
          AgentChatItemType.assistantMessage => AgentChatAssistantMessage(
            item: answer,
          ),
          _ => AgentChatItemRowView(item: answer),
        },
    ];
  }
}

class const _FoldDivider({
  required final Widget label,
  required final bool expanded,
  required final VoidCallback? onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onToggle != null,
      expanded: onToggle == null ? null : expanded,
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Row(
            children: <Widget>[
              Flexible(child: label),
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

/// The turn header: "Working for 12s" ticking once a second while the turn
/// runs and the app is in front, then "Worked for", "Failed after" and the
/// rest from the shared projection.
class const AgentChatTurnHeaderText({
  super.key,
  required final AgentChatTurnSection section,
  final TextStyle? style,
}) extends StatefulWidget {
  @override
  State<AgentChatTurnHeaderText> createState() =>
      _AgentChatTurnHeaderTextState();
}

class _AgentChatTurnHeaderTextState extends State<AgentChatTurnHeaderText> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentChatTurnHeaderText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.working != widget.section.working ||
        oldWidget.section.startedAt != widget.section.startedAt) {
      _sync();
    }
  }

  // TickerMode is off when the route is covered or the tab is not shown, so a
  // label nobody can see stops waking the app up.
  void _sync() {
    _timer?.cancel();
    final ticking =
        widget.section.working &&
        widget.section.startedAt != null &&
        TickerMode.valuesOf(context).enabled;
    _timer = ticking
        ? Timer.periodic(AleraTokens.elapsedTimeTick, (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final text = agentChatTurnHeaderLabel(
      section,
      now: AgentChatElapsedClock.read(context),
    );
    if (section.working) {
      return AgentChatShimmerText(text: text, style: widget.style);
    }
    return Text(text, style: widget.style, maxLines: 1, overflow: .ellipsis);
  }
}

class const _TurnEnded({required final AgentChatTurnSection section})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final turn = section.turn;
    final message = turn?.errorMessage?.trim();
    final label = switch (section.outcome) {
      AgentChatTurnOutcome.stopped => 'Stopped',
      AgentChatTurnOutcome.cancelled => 'Cancelled',
      AgentChatTurnOutcome.interruptedByRestart =>
        'Interrupted when the runtime restarted',
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
