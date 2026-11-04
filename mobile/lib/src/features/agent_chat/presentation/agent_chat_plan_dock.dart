import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:flutter/material.dart';

/// The checklist of the turn that is running now, if it keeps one.
AgentChatItem? agentChatRunningPlan(AgentChatTimelineProjection timeline) {
  for (final entry in timeline.entries.reversed) {
    if (entry case AgentChatTurnEntry(:final section) when section.working) {
      return section.planSteps;
    }
  }
  return null;
}

/// Plan progress pinned above the composer while the turn runs, folded to
/// one line, so the reader sees how far along it is without scrolling back.
class const AgentChatPlanDock({super.key, required final AgentChatItem plan})
    extends StatefulWidget {
  @override
  State<AgentChatPlanDock> createState() => _AgentChatPlanDockState();
}

class _AgentChatPlanDockState extends State<AgentChatPlanDock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.plan.planSteps;
    final done = steps
        .where((step) => step.status == AgentChatPlanStepStatus.completed)
        .length;
    final current = steps
        .where((step) => step.status == AgentChatPlanStepStatus.inProgress)
        .firstOrNull;
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AleraTokens.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        AleraIcons.listView,
                        size: AleraTokens.space16,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(
                        child: Text(
                          current == null
                              ? 'Plan · $done of ${steps.length} done'
                              : 'Plan · $done of ${steps.length} · '
                                    '${current.step}',
                          style: style,
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronUp,
                        size: AleraTokens.space16,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space12,
                0,
                AleraTokens.space12,
                AleraTokens.space12,
              ),
              child: AgentChatPlanSteps(steps: steps),
            ),
        ],
      ),
    );
  }
}
