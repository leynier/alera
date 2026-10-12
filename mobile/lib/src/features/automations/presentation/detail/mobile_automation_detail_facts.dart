import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// When it runs, where, how the last run went, where it is listed and who
/// created it, one fact per line.
class const MobileAutomationDetailFacts({
  required final AutomationRecord automation,
  required final MobileAutomationContext names,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final automation = this.automation;
    final createdBy = automationJsonMap(automation.raw['createdBy']);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraKeyValueRow(
          icon: AleraIcons.schedule,
          label: 'Schedule',
          value: mobileAutomationScheduleLine(automation),
        ),
        AleraKeyValueRow(
          icon: AleraIcons.workspaceMain,
          label: 'Destination',
          value: automationRecordTargetSummary(automation, names),
        ),
        AleraKeyValueRow(
          icon: AleraIcons.restore,
          label: 'Last Run',
          value: switch (automation.lastRun) {
            null => 'No runs yet',
            final run => mobileAutomationLastRunLabel(run),
          },
        ),
        if (automation.associatedWorkspaceId case final workspace?)
          AleraKeyValueRow(
            icon: AleraIcons.section,
            label: 'Shown In',
            value: names.workspaceName(workspace),
          ),
        if (createdBy.isNotEmpty)
          AleraKeyValueRow(
            icon: AleraIcons.account,
            label: 'Created By',
            value: automationActorLabel(createdBy),
          ),
      ],
    );
  }
}

/// The prompt template with its variables highlighted, collapsible, with a
/// copy button.
class const MobileAutomationDetailPrompt({
  required final String prompt,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return AleraCollapsibleSection(
      title: 'Prompt',
      initiallyExpanded: true,
      trailing: AleraIconButton(
        tooltip: 'Copy Prompt',
        icon: AleraIcons.copy,
        onPressed: () => unawaited(() async {
          final messenger = ScaffoldMessenger.of(context);
          await Clipboard.setData(ClipboardData(text: prompt));
          messenger.showSnackBar(
            const SnackBar(content: Text('Prompt copied.')),
          );
        }()),
      ),
      child: SelectableText.rich(
        TextSpan(
          style: style,
          children: <InlineSpan>[
            for (final segment in automationTemplateSegments(prompt))
              TextSpan(
                text: segment.text,
                style: segment.known == null
                    ? null
                    : AleraTokens.monoStyle.copyWith(
                        color: segment.known!
                            ? AleraTokens.info
                            : AleraTokens.error,
                        backgroundColor: AleraTokens.accentSubtle,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
