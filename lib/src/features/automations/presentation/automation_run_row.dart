import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:flutter/material.dart';

/// One run in a history list. Selecting it opens the run panel, which holds
/// every action, so the row itself stays a single tap target.
class const AutomationRunRow({
  required final AutomationRunRecord run,
  required final bool selected,
  required final VoidCallback onTap,
  final String? automationName,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = automationRunStatusLabel(run);
    final theme = Theme.of(context);
    final started = run.startedAt ?? run.scheduledAt;
    final details = <String>[
      ?automationName,
      run.trigger == 'manual' ? 'Manual' : 'Scheduled',
      if (started != null) automationDateTimeLabel(started),
      if (run.finishedAt != null && started != null)
        automationShortDuration(run.finishedAt!.difference(started)),
      if (!run.isFinal && run.lastActivityAt != null)
        'Last activity ${automationRelativeTime(run.lastActivityAt!)}',
    ];
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AleraTokens.accentSubtle,
      onTap: onTap,
      title: Row(
        children: <Widget>[
          Text('#${run.number}', style: theme.textTheme.bodyMedium),
          const SizedBox(width: AleraTokens.space8),
          Flexible(child: AutomationStatusText(status: status)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            details.join(' · '),
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          if (run.summary ?? run.error case final text?)
            Text(text, maxLines: 2, overflow: .ellipsis),
        ],
      ),
    );
  }
}

class const AutomationMissedRunsRow({
  required final AutomationRunHistoryMissed missed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final from = missed.from;
    final to = missed.to;
    final range = from == null || to == null
        ? ''
        : ' · ${automationDateTimeLabel(from)} to ${automationDateTimeLabel(to)}';
    return ListTile(
      dense: true,
      leading: Icon(
        automationStatusIcon(
          const AutomationStatusLabel(label: '', tone: AutomationTone.neutral),
        ),
        size: AleraTokens.iconSm,
        color: AleraTokens.foregroundMuted,
      ),
      title: Text('Missed While Runtime Was Off$range'),
      subtitle: Text(
        '${missed.runs.length} scheduled runs missed their start window and were skipped.',
      ),
    );
  }
}
