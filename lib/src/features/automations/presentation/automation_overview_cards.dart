import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:flutter/material.dart';

/// A titled card of the automation overview.
class const AutomationOverviewCard({
  required final String title,
  required final IconData icon,
  required final Widget child,
  final Widget? trailing,
  final bool padded = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      clipBehavior: .antiAlias,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            AleraTokens.space8,
            AleraTokens.space8,
            AleraTokens.space8,
          ),
          child: SizedBox(
            height: AleraTokens.space32,
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        // Run rows are ListTiles, which paint on the nearest Material.
        Material(
          type: .transparency,
          child: padded
              ? Padding(
                  padding: const EdgeInsets.all(AleraTokens.space16),
                  child: child,
                )
              : child,
        ),
      ],
    );
  }
}

/// One labeled value of the Details card.
class const AutomationDetailRow({
  required final IconData icon,
  required final String label,
  required final String value,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: .start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AleraTokens.space2),
          child: Icon(
            icon,
            size: AleraTokens.iconSm,
            color: AleraTokens.foregroundFaint,
          ),
        ),
        const SizedBox(width: AleraTokens.space8),
        SizedBox(
          width: AleraTokens.automationInfoLabelWidth,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Next run, last run, success rate and run count of an automation.
class const AutomationStatStrip({
  required final AutomationRecord automation,
  required final AutomationDetail detail,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final runs = detail.runs
        .where((run) => run.status != 'misfireSkipped')
        .toList(growable: false);
    final lastFinished = runs.where((run) => run.isFinal).firstOrNull;
    final rated = runs
        .where((run) => _ratedStatuses.contains(run.status))
        .toList(growable: false);
    final succeeded = rated.where((run) => run.status == 'success').length;
    final active = runs.where((run) => run.isActive).length;
    final next = automation.nextRunAt;
    final scheduled = automation.state == 'active' && next != null;
    final lastStatus = lastFinished == null
        ? null
        : automationRunStatusLabel(lastFinished);
    final lastAt = lastFinished?.finishedAt ?? lastFinished?.scheduledAt;
    final tiles = <Widget>[
      _StatTile(
        label: 'Next Run',
        value: scheduled ? automationRelativeTime(next) : 'Not Scheduled',
        caption: scheduled
            ? automationDateTimeLabel(next)
            : automationStateLabel(automation).label,
      ),
      _StatTile(
        label: 'Last Run',
        value: lastStatus?.label ?? 'No Runs Yet',
        valueColor: lastStatus == null
            ? null
            : automationToneColor(lastStatus.tone),
        caption: lastAt == null
            ? 'Run it now to try it.'
            : '#${lastFinished!.number} · ${automationRelativeTime(lastAt)}',
      ),
      _StatTile(
        label: 'Success Rate',
        value: rated.isEmpty
            ? '-'
            : '${(succeeded * 100 / rated.length).round()}%',
        valueColor: rated.isEmpty
            ? null
            : succeeded == rated.length
            ? AleraTokens.success
            : null,
        caption: rated.isEmpty
            ? 'No finished runs'
            : '$succeeded of ${rated.length} succeeded',
      ),
      _StatTile(
        label: 'Runs',
        value: '${runs.length}',
        caption: active == 0 ? 'None running' : '$active running now',
        valueColor: active == 0 ? null : AleraTokens.info,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AleraTokens.space12;
        final columns =
            constraints.maxWidth >= AleraTokens.wideContentBreakpoint ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// Final statuses that count toward the success rate. Skips are not attempts.
const Set<String> _ratedStatuses = <String>{
  'success',
  'failure',
  'blocked',
  'timeout',
};

class const _StatTile({
  required final String label,
  required final String value,
  required final String caption,
  final Color? valueColor,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(label, style: AleraTokens.labelFaintStyle),
          const SizedBox(height: AleraTokens.space6),
          Text(
            value,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: valueColor ?? AleraTokens.foreground,
              fontWeight: .w600,
            ),
          ),
          const SizedBox(height: AleraTokens.space2),
          Text(
            caption,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
