import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tool_details.dart';
import 'package:flutter/material.dart';

/// One item that is not a prompt, an answer or a grouped action: reasoning,
/// progress narration, notices, compaction and errors.
class const AgentChatItemRowView({super.key, required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => switch (item.type) {
    AgentChatItemType.reasoning => _Expandable(
      icon: AleraIcons.sparkles,
      label: agentChatReasoningLabel(item),
      streaming: item.isInProgress,
      foldKey: agentChatReasoningFoldKey(item.id),
      child: AgentChatToolDetails(item: item),
    ),
    AgentChatItemType.assistantMessage => Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: item.isPartialContinuation
          ? AgentChatPartialText(text: item.text)
          : AgentChatMarkdown(text: item.text),
    ),
    AgentChatItemType.contextCompaction => _Line(
      icon: AleraIcons.contextCompact,
      label: item.isFailed
          ? 'Compaction failed'
          : item.isInProgress
          ? 'Compacting context'
          : 'Compacted context',
      streaming: item.isInProgress,
      color: item.isFailed ? AleraTokens.error : AleraTokens.foregroundMuted,
    ),
    AgentChatItemType.error => AgentChatNoticeCard(
      title: item.title ?? 'Error',
      body: item.text.trim().isNotEmpty ? item.text : item.detail,
      tone: AleraTokens.error,
      icon: AleraIcons.loadFailed,
    ),
    AgentChatItemType.notice => AgentChatNoticeCard(
      title: item.title ?? 'Notice',
      body: item.text.trim().isNotEmpty ? item.text : item.detail,
      tone: item.isFailed ? AleraTokens.error : AleraTokens.warning,
      icon: AleraIcons.warning,
    ),
    AgentChatItemType.plan => AgentChatPlanCard(item: item),
    _ => _Expandable(
      icon: AleraIcons.info,
      label: item.title ?? item.detail ?? 'Activity',
      streaming: item.isInProgress,
      foldKey: agentChatActionFoldKey(item.id),
      child: item.hasDetails ? AgentChatToolDetails(item: item) : null,
    ),
  };
}

/// A tinted callout for warnings and errors the agent or runtime reported.
class const AgentChatNoticeCard({
  super.key,
  required final String title,
  required final Color tone,
  required final IconData icon,
  final String? body,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = body?.trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: AleraTokens.statusTintAlpha),
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          Icon(icon, size: AleraTokens.space16, color: tone),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: AleraTokens.space4,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(color: tone),
                ),
                if (text.isNotEmpty) AgentChatMarkdown(text: text),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A proposed plan: its text, or its checklist when the provider keeps one.
class const AgentChatPlanCard({super.key, required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space12),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(AleraIcons.listView, size: AleraTokens.space16),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: item.isInProgress
                    ? AgentChatShimmerText(
                        text: 'Planning',
                        style: theme.textTheme.labelMedium,
                      )
                    : Text(
                        item.title ?? 'Plan',
                        style: theme.textTheme.labelMedium,
                      ),
              ),
            ],
          ),
          if ((item.explanation ?? '').trim().isNotEmpty)
            AgentChatMarkdown(text: item.explanation!),
          if (item.planSteps.isNotEmpty)
            AgentChatPlanSteps(steps: item.planSteps)
          else if (item.text.trim().isNotEmpty)
            AgentChatMarkdown(text: item.text),
          if (AgentChatHistoryActions.maybeOf(context)?.onImplementPlan
              case final implement?
              when !item.isInProgress &&
                  (item.text.trim().isNotEmpty || item.planSteps.isNotEmpty))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => implement(item),
                icon: const Icon(AleraIcons.workspaceChildren),
                label: const Text('Implement In New Workspace'),
              ),
            ),
        ],
      ),
    );
  }
}

class const AgentChatPlanSteps({
  super.key,
  required final List<AgentChatPlanStep> steps,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space4,
      children: <Widget>[
        for (final step in steps)
          Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Icon(
                switch (step.status) {
                  AgentChatPlanStepStatus.completed => AleraIcons.success,
                  AgentChatPlanStepStatus.inProgress => AleraIcons.loading,
                  AgentChatPlanStepStatus.pending => AleraIcons.circle,
                },
                size: AleraTokens.space16,
                color: step.status == AgentChatPlanStepStatus.completed
                    ? AleraTokens.success
                    : AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  step.step,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: step.status == AgentChatPlanStepStatus.completed
                        ? AleraTokens.foregroundMuted
                        : AleraTokens.foreground,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class const _Line({
  required final IconData icon,
  required final String label,
  required final Color color,
  final bool streaming = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AleraTokens.space16, color: color),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: streaming
                ? AgentChatShimmerText(text: label, style: style)
                : Text(label, style: style),
          ),
        ],
      ),
    );
  }
}

/// A one-line row that opens to its details on tap.
class const _Expandable({
  required final IconData icon,
  required final String label,
  required final bool streaming,
  required final String foldKey,
  required final Widget? child,
}) extends StatefulWidget {
  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  late bool _expanded = agentChatFoldExpanded(
    context,
    widget.foldKey,
    fallback: false,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(context, widget.foldKey, expanded: _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Semantics(
          button: child != null,
          expanded: child == null ? null : _expanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: child == null ? null : _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.icon,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: widget.streaming
                        ? AgentChatShimmerText(text: widget.label, style: style)
                        : Text(widget.label, style: style, overflow: .ellipsis),
                  ),
                  if (child != null)
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
        if (_expanded && child != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AleraTokens.space24,
              bottom: AleraTokens.space8,
            ),
            child: child,
          ),
      ],
    );
  }
}
