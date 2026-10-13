import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';

/// The audit trail of one automation, newest first as the runtime sends it.
class const AutomationActivityTab({
  required final List<JsonMap> events,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text(
        'No activity yet.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final event in events)
          AleraActivityRow(
            title: automationActivityLabel(event),
            subtitle: <String>[
              automationActorLabel(automationJsonMap(event['actor'])),
              if (automationJsonDate(event['createdAt']) case final date?)
                automationDateTimeLabel(date),
            ].join(' · '),
            metadata: automationJsonOptionalString(
              automationJsonMap(event['details'])['reason'],
            ),
            onPressed: () {},
          ),
      ],
    );
  }
}
