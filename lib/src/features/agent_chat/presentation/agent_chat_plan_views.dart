import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_plan_delegation.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A plan the agent proposed in plan mode. Long plans show a preview until
/// expanded; the latest one offers to refine it from the composer in plan
/// mode or to leave plan mode and implement it, and any settled one can be
/// implemented in a new workspace instead.
class const AgentChatProposedPlanView({
  super.key,
  required final AgentChatItem item,
  required final AgentChatExpansion expansion,
  required final ValueChanged<String> onOpenLink,
  required final VoidCallback? onImplement,
  final VoidCallback? onRefine,
}) extends StatefulWidget {
  @override
  State<AgentChatProposedPlanView> createState() =>
      _AgentChatProposedPlanViewState();
}

class _AgentChatProposedPlanViewState extends State<AgentChatProposedPlanView> {
  String get _key => agentChatPlanFoldKey(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final expanded = widget.expansion.isExpanded(_key, byDefault: false);
    final markdown = AgentChatMarkdown(
      data: item.text,
      onOpenLink: widget.onOpenLink,
    );
    return Container(
      key: ValueKey<String>('agent-chat-plan-${item.id}'),
      margin: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.plan,
                size: AleraTokens.iconMd,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: item.isInProgress
                    ? AleraShimmerText(
                        text: 'Drafting Plan',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      )
                    : Text('Proposed Plan', style: theme.textTheme.labelMedium),
              ),
              TextButton(
                onPressed: () => setState(
                  () => widget.expansion.set(_key, expanded: !expanded),
                ),
                child: Text(expanded ? 'Show Less' : 'Show Full Plan'),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          if (expanded)
            markdown
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: AleraTokens.agentChatPlanPreviewMaxHeight,
              ),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: markdown,
                ),
              ),
            ),
          if (!item.isInProgress) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            // Implement In New Workspace hides itself without chat tasks, so
            // the row may hold only Refine and Implement Plan, or nothing.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                ChatTaskImplementPlanButton(plan: item),
                if (widget.onRefine case final VoidCallback refine)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('agent-chat-refine-plan'),
                    onPressed: refine,
                    icon: const Icon(AleraIcons.edit, size: AleraTokens.iconMd),
                    label: const Text('Refine'),
                  ),
                if (widget.onImplement case final VoidCallback implement)
                  FilledButton.icon(
                    key: const ValueKey<String>('agent-chat-implement-plan'),
                    onPressed: implement,
                    icon: const Icon(
                      AleraIcons.check,
                      size: AleraTokens.iconMd,
                    ),
                    label: const Text('Implement Plan'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The plan Implement Plan and Refine act on: the newest proposed plan of
/// the latest turn, while the chat is idle in plan mode.
String? agentChatImplementablePlanId(AgentChatViewState state) {
  final thread = state.thread;
  final projection = state.projection;
  if (thread == null ||
      projection == null ||
      thread.session.busy ||
      thread.session.interactionMode != AgentChatInteractionMode.plan) {
    return null;
  }
  for (final entry in projection.entries.reversed) {
    if (entry is! AgentChatTurnEntry) continue;
    for (final answer in entry.section.answers.reversed) {
      if (answer.type == AgentChatItemType.plan && !answer.isInProgress) {
        return answer.id;
      }
    }
    return null;
  }
  return null;
}

/// The running turn's checklist, docked above the composer while the agent
/// works through it.
class const AgentChatPlanProgressDock({
  super.key,
  required final AgentChatItem item,
}) extends StatefulWidget {
  @override
  State<AgentChatPlanProgressDock> createState() =>
      _AgentChatPlanProgressDockState();
}

class _AgentChatPlanProgressDockState extends State<AgentChatPlanProgressDock> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = widget.item.planSteps;
    final done = steps
        .where((step) => step.status == AgentChatPlanStepStatus.completed)
        .length;
    return Container(
      key: const ValueKey<String>('agent-chat-plan-progress'),
      constraints: const BoxConstraints(
        maxWidth: AleraTokens.agentChatDockMaxWidth,
        maxHeight: AleraTokens.agentChatPlanProgressMaxHeight,
      ),
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.planActive,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    'Plan · $done of ${steps.length} done',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Icon(
                  _collapsed ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
          if (!_collapsed)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: AleraTokens.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (widget.item.explanation case final String explanation)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AleraTokens.space6,
                        ),
                        child: Text(
                          explanation,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                    for (final step in steps) _PlanStepRow(step: step),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class const _PlanStepRow({required final AgentChatPlanStep step})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (step.status) {
      AgentChatPlanStepStatus.completed => (
        AleraIcons.check,
        AleraTokens.success,
      ),
      AgentChatPlanStepStatus.inProgress => (
        AleraIcons.chevronRight,
        AleraTokens.info,
      ),
      AgentChatPlanStepStatus.pending => (
        AleraIcons.plan,
        AleraTokens.foregroundFaint,
      ),
    };
    final style = theme.textTheme.bodySmall?.copyWith(
      // The running step shimmers from muted to foreground, so it starts muted.
      color: step.status == AgentChatPlanStepStatus.pending
          ? AleraTokens.foreground
          : AleraTokens.foregroundMuted,
      decoration: step.status == AgentChatPlanStepStatus.completed
          ? TextDecoration.lineThrough
          : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space2),
            child: Icon(icon, size: AleraTokens.iconSm, color: color),
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: step.status == AgentChatPlanStepStatus.inProgress
                ? AleraShimmerText(text: step.step, style: style)
                : Text(step.step, style: style),
          ),
        ],
      ),
    );
  }
}
