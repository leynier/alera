import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/automation_run_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs whose own workspace is [workspaceId]. Kept apart from "Scheduled
/// Here": where a run happened never makes its automation belong here.
class const AutomationWorkspaceRuns({
  required final String workspaceId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(automationRecentRunsProvider);
    final automations =
        ref.watch(automationCatalogProvider).value ??
        const <AutomationRecord>[];
    final location = ref.watch(automationsNavigationProvider);
    final here = (runs.value ?? const <AutomationRunRecord>[])
        .where((run) => run.workspaceId == workspaceId)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        const AleraSectionHeader(label: 'Runs In This Workspace'),
        if (runs.value == null && runs.hasError)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text('Runs are unavailable: ${runs.error}'),
          )
        else if (here.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              'No automation runs used this workspace recently.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final run in here)
            AutomationRunRow(
              run: run,
              selected: run.id == location.selectedRunId,
              automationName: automations
                  .where((item) => item.id == run.automationId)
                  .firstOrNull
                  ?.name,
              onTap: () => ref
                  .read(automationsNavigationProvider.notifier)
                  .selectRun(run.automationId, run.id),
            ),
      ],
    );
  }
}
