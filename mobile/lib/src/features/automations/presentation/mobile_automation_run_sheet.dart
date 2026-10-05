import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Set<String> _runAgainStatuses = <String>{
  'failure',
  'timeout',
  'cancelled',
  'blocked',
  'success',
};

String mobileLaunchKindLabel(String? kind) => switch (kind) {
  'resume' => 'Resumed Conversation',
  'contextRetry' => 'Retried With Context',
  _ => 'Started',
};

Future<void> showMobileAutomationRun(
  BuildContext context, {
  required String hostId,
  required String automationId,
  required String runId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    builder: (_, controller) => MobileAutomationRunSheet(
      hostId: hostId,
      automationId: automationId,
      runId: runId,
      scrollController: controller,
    ),
  ),
);

/// One run: status, recovery, attempts and its actions. Completed history is
/// never edited; Run Again always creates a new run.
class const MobileAutomationRunSheet({
  required final String hostId,
  required final String automationId,
  required final String runId,
  final ScrollController? scrollController,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref
        .watch(mobileAutomationDetailProvider(hostId, automationId))
        .value;
    final run = detail?.runs.where((item) => item.id == runId).firstOrNull;
    if (detail == null || run == null) {
      return const Padding(
        padding: AleraTokens.pagePadding,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final repository = ref
        .watch(mobileAutomationRepositoryProvider(hostId))
        .value;
    final observe = repository?.supportsObserve ?? false;
    final theme = Theme.of(context);
    final status = automationRunStatusLabel(run);
    final actions = MobileAutomationActions(
      ref,
      hostId,
      ScaffoldMessenger.of(context),
    );
    final previous = detail.runs
        .where((item) => item.id == run.continueFromRunId)
        .firstOrNull;
    final continuations = detail.runs
        .where((item) => item.continueFromRunId == run.id)
        .toList(growable: false);
    final deadline = run.absoluteDeadlineAt;
    return ListView(
      controller: scrollController,
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Run #${run.number}', style: theme.textTheme.titleLarge),
            const SizedBox(width: AleraTokens.spaceSm),
            Flexible(child: MobileAutomationStatusText(status: status)),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        if (run.recovery.isActive)
          AleraNotice(
            message: deadline == null
                ? '${status.label}. Alera recovers this run on its own.'
                : '${status.label}. Alera recovers this run on its own and gives up at ${automationDateTimeLabel(deadline)}.',
          )
        else if (run.recovery.status == AutomationRecoveryStatus.exhausted)
          const AleraNotice(
            message: 'Recovery used every attempt. Run Again starts a new run.',
          ),
        if (run.ownerReserved)
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.spaceSm),
            child: AleraNotice(message: automationOwnerReservedMessage),
          ),
        if (run.takenOver)
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.spaceSm),
            child: AleraNotice(
              message: 'This run was taken over. Automatic recovery is stopped for it.',
            ),
          ),
        if (run.summary ?? run.error case final text?) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          SelectableText(text),
        ],
        if (previous != null) Text('Continued from run #${previous.number}.'),
        for (final next in continuations)
          Text('Continued in run #${next.number}.'),
        if (detail.attemptsFor(run.id) case final attempts
            when attempts.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text('Attempts', style: theme.textTheme.titleSmall),
          for (final attempt in attempts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Attempt ${attempt.number} · ${mobileLaunchKindLabel(attempt.launchKind)}',
              ),
              subtitle: Text(
                <String>[
                  attempt.status,
                  if (attempt.interruptionCode case final code?)
                    'Interrupted: $code',
                  ?attempt.error,
                ].join(' · '),
              ),
              trailing: attempt.tabId == null || !observe
                  ? null
                  : TextButton(
                      onPressed: () => unawaited(
                        _openTerminal(context, ref, run, tabId: attempt.tabId),
                      ),
                      child: const Text('Watch'),
                    ),
            ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        Wrap(
          spacing: AleraTokens.spaceSm,
          runSpacing: AleraTokens.spaceSm,
          children: <Widget>[
            if (run.tabId != null && run.workspaceId != null) ...<Widget>[
              FilledButton.tonal(
                onPressed: () => unawaited(_openTerminal(context, ref, run)),
                child: Text(
                  run.takenOver
                      ? 'Open Terminal'
                      : observe
                      ? 'Watch Terminal'
                      : 'Open And Take Over',
                ),
              ),
              if (observe && !run.takenOver && !run.isFinal)
                OutlinedButton(
                  onPressed: () =>
                      unawaited(actions.takeOver(run.id, tabId: run.tabId)),
                  child: const Text('Take Over · Stops Automatic Recovery'),
                ),
            ],
            if (run.workspaceId != null)
              OutlinedButton(
                onPressed: () => unawaited(
                  _openTerminal(context, ref, run, workspaceOnly: true),
                ),
                child: const Text('Open Workspace'),
              ),
            if (run.status == 'waitingForUser') ...<Widget>[
              OutlinedButton(
                onPressed: () => unawaited(actions.resumeWaiting(run)),
                child: const Text('Resume'),
              ),
              OutlinedButton(
                onPressed: () => unawaited(actions.extendWaiting(run)),
                child: const Text('Extend 1h'),
              ),
            ],
            if (run.isActive)
              TextButton(
                onPressed: () => unawaited(actions.cancelRun(run)),
                child: Text(
                  run.recovery.isActive ? 'Stop Recovery' : 'Cancel Run',
                ),
              ),
            if (run.isFinal &&
                _runAgainStatuses.contains(run.status) &&
                !detail.automation.isTrashed)
              FilledButton(
                onPressed: () async {
                  final continueFrom = await showAleraActionSheet<bool>(
                    context,
                    entries: <AleraActionSheetEntry<bool>>[
                      AleraActionSheetEntry<bool>(
                        value: true,
                        label: 'Continue From Run #${run.number}',
                        leading: const Icon(AleraIcons.restore),
                      ),
                      const AleraActionSheetEntry<bool>(
                        value: false,
                        label: 'Start Fresh',
                        leading: Icon(AleraIcons.add),
                      ),
                    ],
                  );
                  if (continueFrom == null) return;
                  await actions.runNow(
                    detail.automation,
                    continueFromRunId: continueFrom ? run.id : null,
                  );
                },
                child: const Text('Run Again'),
              ),
          ],
        ),
      ],
    );
  }

  /// With observation support the tab opens read-only; without it the attach
  /// takes the run over, which is what the button label says.
  Future<void> _openTerminal(
    BuildContext context,
    WidgetRef ref,
    AutomationRunRecord run, {
    String? tabId,
    bool workspaceOnly = false,
  }) async {
    final names = await ref.read(
      mobileAutomationContextProvider(hostId).future,
    );
    final workspace = names.workspace(run.workspaceId);
    if (!context.mounted) return;
    if (workspace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The workspace of run #${run.number} is no longer available.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceTabsScreen(
          hostId: hostId,
          workspace: workspace,
          initialTabId: workspaceOnly ? null : tabId ?? run.tabId,
          selectFallbackTab: workspaceOnly,
        ),
      ),
    );
  }
}
