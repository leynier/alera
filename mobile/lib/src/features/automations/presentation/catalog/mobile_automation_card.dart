import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:flutter/material.dart';

const List<AutomationBucket?> _buckets = <AutomationBucket?>[
  null,
  .active,
  .paused,
  .drafts,
  .needsAttention,
  .completed,
  .trash,
];

/// Status buckets as one horizontally scrolling row of toggles. Needs
/// Attention carries its count so a problem is visible from any bucket.
class const MobileAutomationBucketChips({
  required final AutomationBucket? selected,
  required final Map<AutomationBucket, int> counts,
  required final ValueChanged<AutomationBucket?> onSelected,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (final (index, bucket) in _buckets.indexed)
          Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 0 : AleraTokens.spaceXs,
            ),
            child: ChoiceChip(
              label: Text(switch (bucket) {
                null => 'All',
                AutomationBucket.needsAttention =>
                  '${bucket.label} · ${counts[bucket] ?? 0}',
                _ => bucket.label,
              }),
              selected: selected == bucket,
              onSelected: (_) => onSelected(bucket),
            ),
          ),
      ],
    ),
  );
}

/// One definition in the list: how its last run went, its name and state,
/// when it runs, where, what it is bound to, and what needs attention.
class const MobileAutomationCard({
  required final AutomationRecord automation,
  required final MobileAutomationContext names,
  required final VoidCallback onOpen,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final automation = this.automation;
    final state = automationStateLabel(automation);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final lastRun = automation.lastRun;
    final readinessError = automation.isEditable
        ? automation.readiness?.errors.firstOrNull?.message
        : null;
    final alert = automation.attention?.message ?? readinessError;
    return Card(
      margin: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space6),
                child: Semantics(
                  label: lastRun == null
                      ? 'No runs yet'
                      : 'Last run: ${mobileAutomationLastRunLabel(lastRun)}',
                  child: AleraStatusDot(
                    active: lastRun != null,
                    color: lastRun == null
                        ? AleraTokens.foregroundFaint
                        : mobileAutomationToneColor(
                            automationRunStatusTone(lastRun.status),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            automation.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                        const SizedBox(width: AleraTokens.spaceSm),
                        AleraBadge(
                          label: state.label,
                          tone: mobileAutomationBadgeTone(state.tone),
                        ),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.spaceXs),
                    Text(
                      mobileAutomationScheduleLine(automation),
                      style: muted,
                    ),
                    Text(
                      automationRecordTargetSummary(automation, names),
                      style: muted,
                      maxLines: 2,
                      overflow: .ellipsis,
                    ),
                    if (automation.boundTargetSummary case final bound?)
                      Row(
                        children: <Widget>[
                          const Icon(
                            AleraIcons.link,
                            size: AleraTokens.iconSm,
                            color: AleraTokens.foregroundMuted,
                          ),
                          const SizedBox(width: AleraTokens.spaceXs),
                          Flexible(
                            child: Text(
                              'bound: $bound',
                              style: muted,
                              maxLines: 1,
                              overflow: .ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (alert != null)
                      Text(
                        alert,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: automation.attention != null
                              ? AleraTokens.warning
                              : AleraTokens.error,
                        ),
                      ),
                    if (automation.createdByAgent)
                      Text(
                        'Created by agent ${automation.createdByLabel ?? ''}'
                            .trim(),
                        style: muted,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
