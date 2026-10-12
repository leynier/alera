import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs whose own workspace is [workspaceId]. Where a run happened never
/// makes its automation belong to the workspace.
class const MobileAutomationWorkspaceRuns({
  required final String hostId,
  required final String workspaceId,
  required final List<AutomationRecord> automations,
  required final ValueChanged<AutomationRunRecord> onOpen,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs =
        ref.watch(mobileAutomationRecentRunsProvider(hostId)).value ??
        const <AutomationRunRecord>[];
    final here = runs
        .where((run) => run.workspaceId == workspaceId)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        const AleraSectionHeader(label: 'Runs In This Workspace'),
        if (here.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.spaceMd),
            child: Text(
              'No automation runs used this workspace recently.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          )
        else
          for (final run in here)
            MobileAutomationRunRow(
              run: run,
              automationName: automations
                  .where((item) => item.id == run.automationId)
                  .firstOrNull
                  ?.name,
              onTap: () => onOpen(run),
            ),
      ],
    );
  }
}
