import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:flutter/material.dart';

class const MobileAutomationRunRow({
  required final AutomationRunRecord run,
  required final VoidCallback onTap,
  final String? automationName,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final started = run.startedAt ?? run.scheduledAt;
    final details = <String>[
      ?automationName,
      run.trigger == 'manual' ? 'Manual' : 'Scheduled',
      if (started != null) automationDateTimeLabel(started),
      if (!run.isFinal && run.lastActivityAt != null)
        'Last activity ${automationRelativeTime(run.lastActivityAt!)}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Row(
        children: <Widget>[
          Text('#${run.number}'),
          const SizedBox(width: AleraTokens.spaceSm),
          Flexible(
            child: MobileAutomationStatusText(
              status: automationRunStatusLabel(run),
            ),
          ),
        ],
      ),
      subtitle: Text(
        <String>[details.join(' · '), ?(run.summary ?? run.error)].join('\n'),
        maxLines: 3,
        overflow: .ellipsis,
      ),
    );
  }
}

class const MobileMissedRunsRow({
  required final AutomationRunHistoryMissed missed,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final from = missed.from;
    final to = missed.to;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Missed While Runtime Was Off'),
      subtitle: Text(
        <String>[
          if (from != null && to != null)
            '${automationDateTimeLabel(from)} to ${automationDateTimeLabel(to)}',
          '${missed.runs.length} scheduled runs missed their start window and were skipped.',
        ].join('\n'),
      ),
    );
  }
}
