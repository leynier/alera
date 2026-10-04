import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Set<String> _runAgainStatuses = <String>{
  'failure',
  'timeout',
  'cancelled',
  'blocked',
  'success',
};

String automationLaunchKindLabel(String? kind) => switch (kind) {
  'resume' => 'Resumed Conversation',
  'contextRetry' => 'Retried With Context',
  _ => 'Started',
};

/// Everything about one run: status and recovery, attempts, links to the
/// runs it continues or that continue it, and the run's actions. Completed
/// history is never edited here; Run Again always creates a new run.
class const AutomationRunPanel({
  required final AutomationRecord automation,
  required final AutomationRunRecord run,
  required final List<AutomationRunRecord> runs,
  required final List<AutomationAttemptRecord> attempts,
  required final ValueChanged<String> onSelectRun,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = AutomationActions(ref);
    final observe =
        ref.watch(automationRuntimeCapabilitiesProvider).value?.observe ??
        false;
    final status = automationRunStatusLabel(run);
    final previous = runs
        .where((item) => item.id == run.continueFromRunId)
        .firstOrNull;
    final continuations = runs
        .where((item) => item.continueFromRunId == run.id)
        .toList(growable: false);
    final deadline = run.absoluteDeadlineAt;
    final buttons = <Widget>[
      if (run.tabId != null) ..._terminalButtons(actions, observe),
      if (run.workspaceId != null)
        OutlinedButton(
          onPressed: () => unawaited(actions.openRunWorkspace(run)),
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
          child: Text(run.recovery.isActive ? 'Stop Recovery' : 'Cancel Run'),
        ),
      if (run.isFinal &&
          _runAgainStatuses.contains(run.status) &&
          !automation.isTrashed)
        _RunAgainButton(automation: automation, run: run),
    ];
    return AleraPanel(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Run #${run.number}', style: theme.textTheme.titleSmall),
                  const SizedBox(width: AleraTokens.space8),
                  Flexible(child: AutomationStatusText(status: status)),
                ],
              ),
              const SizedBox(height: AleraTokens.space8),
              if (run.recovery.isActive)
                AleraInlineNotice(
                  tone: status.tone == AutomationTone.warning
                      ? .warning
                      : .info,
                  message: deadline == null
                      ? '${status.label}. Alera recovers this run on its own.'
                      : '${status.label}. Alera recovers this run on its own and gives up at ${automationDateTimeLabel(deadline)}.',
                )
              else if (run.recovery.status ==
                  AutomationRecoveryStatus.exhausted)
                const AleraInlineNotice(
                  tone: .error,
                  message: 'Recovery used every attempt. Run Again starts a new run.',
                ),
              if (run.ownerReserved)
                const Padding(
                  padding: EdgeInsets.only(top: AleraTokens.space8),
                  child: AleraInlineNotice(
                    tone: .warning,
                    message: automationOwnerReservedMessage,
                  ),
                ),
              if (run.takenOver)
                const Padding(
                  padding: EdgeInsets.only(top: AleraTokens.space8),
                  child: AleraInlineNotice(
                    message: 'You took over this run. Automatic recovery is stopped for it.',
                  ),
                ),
              if (run.summary ?? run.error case final text?) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                SelectableText(text),
              ],
              if (previous != null || continuations.isNotEmpty) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                Wrap(
                  spacing: AleraTokens.space8,
                  children: <Widget>[
                    if (previous != null)
                      TextButton(
                        onPressed: () => onSelectRun(previous.id),
                        child: Text('Continued From #${previous.number}'),
                      ),
                    for (final next in continuations)
                      TextButton(
                        onPressed: () => onSelectRun(next.id),
                        child: Text('Continued In #${next.number}'),
                      ),
                  ],
                ),
              ],
              if (attempts.isNotEmpty) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                Text('Attempts', style: theme.textTheme.labelMedium),
                for (final attempt in attempts)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Attempt ${attempt.number} · ${automationLaunchKindLabel(attempt.launchKind)}',
                    ),
                    subtitle: Text(
                      <String>[
                        attempt.status,
                        if (attempt.interruptionCode case final code?)
                          'Interrupted: $code',
                        if (attempt.startedAt case final started?)
                          automationDateTimeLabel(started),
                        ?attempt.error,
                      ].join(' · '),
                    ),
                    trailing: attempt.tabId == null || !observe
                        ? null
                        : TextButton(
                            onPressed: () => unawaited(
                              actions.openTerminalTab(
                                run.workspaceId,
                                attempt.tabId,
                                label: 'attempt ${attempt.number}',
                              ),
                            ),
                            child: const Text('Watch'),
                          ),
                  ),
              ],
              if (run.renderedPrompt case final prompt?)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Prompt Sent'),
                  children: <Widget>[SelectableText(prompt)],
                ),
              if (buttons.isNotEmpty) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: buttons,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _terminalButtons(AutomationActions actions, bool observe) {
    if (!observe) {
      return <Widget>[
        FilledButton.tonal(
          onPressed: () => unawaited(actions.openRunTerminal(run)),
          child: Text(run.takenOver ? 'Open Terminal' : 'Open And Take Over'),
        ),
      ];
    }
    return <Widget>[
      FilledButton.tonal(
        onPressed: () => unawaited(actions.openRunTerminal(run)),
        child: Text(run.takenOver ? 'Open Terminal' : 'Watch Terminal'),
      ),
      if (!run.takenOver && !run.isFinal)
        OutlinedButton(
          onPressed: () => unawaited(actions.takeOver(run)),
          child: const Text('Take Over · Stops Automatic Recovery'),
        ),
    ];
  }
}

class const _RunAgainButton({
  required final AutomationRecord automation,
  required final AutomationRunRecord run,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = AutomationActions(ref);
    return FilledButton(
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        final overlay =
            Navigator.of(context).overlay!.context.findRenderObject()!
                as RenderBox;
        final origin = box.localToGlobal(
          Offset(0, box.size.height),
          ancestor: overlay,
        );
        final continueFrom = await showMenu<bool>(
          context: context,
          position: RelativeRect.fromRect(
            origin & Size.zero,
            Offset.zero & overlay.size,
          ),
          items: <PopupMenuEntry<bool>>[
            AleraDropdownEntry<bool>(
              value: true,
              leading: const Icon(AleraIcons.restore, size: AleraTokens.iconMd),
              label: 'Continue From Run #${run.number}',
            ),
            const AleraDropdownEntry<bool>(
              value: false,
              leading: Icon(AleraIcons.add, size: AleraTokens.iconMd),
              label: 'Start Fresh',
            ),
          ],
        );
        if (continueFrom == null) return;
        await actions.runNow(
          automation,
          continueFromRunId: continueFrom ? run.id : null,
        );
      },
      child: const Text('Run Again'),
    );
  }
}
