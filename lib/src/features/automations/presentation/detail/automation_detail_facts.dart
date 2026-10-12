import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/catalog/automation_catalog_row.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When it runs, where, how the last run went, where it is listed and who
/// created it, one fact per line.
class const AutomationDetailFacts({
  required final AutomationRecord automation,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(automationWorkbenchContextProvider);
    final automation = this.automation;
    final createdBy = automationJsonMap(automation.raw['createdBy']);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraKeyValueRow(
          icon: AleraIcons.schedule,
          label: 'Schedule',
          value: automationScheduleLine(automation),
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
            final run => automationLastRunLabel(run),
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
