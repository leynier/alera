import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_confirmations.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:flutter/material.dart';

enum _RunNowOption { defaults, withoutPrecheck, queue, parallel }

enum _MoreAction { clone, pauseAndCancel, trash }

/// The lifecycle actions of one automation: activate, pause or resume (or
/// restore from Trash), Run Now with its overrides, and Edit, which reads Fix
/// Problem while something needs attention.
class const MobileAutomationDetailActions({
  required final String hostId,
  required final AutomationRecord automation,
  required final MobileAutomationActions actions,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final automation = this.automation;
    final state = automation.state;
    return Wrap(
      spacing: AleraTokens.spaceSm,
      runSpacing: AleraTokens.spaceSm,
      children: <Widget>[
        if (state == 'draft')
          FilledButton(
            onPressed: () => unawaited(actions.activate(automation)),
            child: const Text('Activate'),
          ),
        if (state == 'active')
          OutlinedButton(
            onPressed: () => unawaited(actions.pause(automation)),
            child: Text(
              automation.activeRunCount > 0
                  ? 'Pause · Runs Keep Going'
                  : 'Pause',
            ),
          ),
        if (state == 'paused' || state == 'blocked')
          FilledButton(
            onPressed: () => unawaited(actions.resume(automation)),
            child: const Text('Resume'),
          ),
        if (automation.isTrashed)
          FilledButton(
            onPressed: () => unawaited(actions.restore(automation)),
            child: const Text('Restore'),
          )
        else
          FilledButton.tonal(
            onPressed: () => unawaited(_runNow(context)),
            child: Text(automation.isCompleted ? 'Run Again' : 'Run Now'),
          ),
        if (automation.isEditable)
          OutlinedButton(
            onPressed: () => unawaited(
              showMobileAutomationComposer(
                context,
                hostId: hostId,
                editing: automation,
              ),
            ),
            child: Text(automation.attention == null ? 'Edit' : 'Fix Problem'),
          ),
      ],
    );
  }

  /// The sheet's first entry runs with the definition's own policy; the
  /// others are the explicit overrides.
  Future<void> _runNow(BuildContext context) async {
    final option = await showAleraActionSheet<_RunNowOption>(
      context,
      entries: <AleraActionSheetEntry<_RunNowOption>>[
        const AleraActionSheetEntry(
          value: _RunNowOption.defaults,
          label: 'Run Now',
          leading: Icon(AleraIcons.agent),
        ),
        if (automation.precheck != null)
          const AleraActionSheetEntry(
            value: _RunNowOption.withoutPrecheck,
            label: 'Run Without Precheck',
            leading: Icon(AleraIcons.cancel),
          ),
        const AleraActionSheetEntry(
          value: _RunNowOption.queue,
          label: 'Queue After Active Run',
          leading: Icon(AleraIcons.queuedMessage),
        ),
        const AleraActionSheetEntry(
          value: _RunNowOption.parallel,
          label: 'Run In Parallel',
          leading: Icon(AleraIcons.split),
        ),
      ],
    );
    final run = await switch (option) {
      null => Future<AutomationRunRecord?>.value(),
      _RunNowOption.defaults => actions.runNow(automation),
      _RunNowOption.withoutPrecheck => actions.runNow(
        automation,
        precheck: false,
      ),
      _RunNowOption.queue => actions.runNow(automation, overlap: 'queue'),
      _RunNowOption.parallel => actions.runNow(
        automation,
        overlap: 'forceParallel',
      ),
    };
    if (run != null && run.id.isNotEmpty && context.mounted) {
      unawaited(
        showMobileAutomationRun(
          context,
          hostId: hostId,
          automationId: automation.id,
          runId: run.id,
        ),
      );
    }
  }
}

/// Clone, Pause And Cancel Runs and Move To Trash. The two destructive ones
/// ask first.
Future<void> showMobileAutomationMoreSheet(
  BuildContext context, {
  required String hostId,
  required AutomationRecord automation,
  required MobileAutomationActions actions,
}) async {
  final action = await showAleraActionSheet<_MoreAction>(
    context,
    entries: <AleraActionSheetEntry<_MoreAction>>[
      const AleraActionSheetEntry(
        value: _MoreAction.clone,
        label: 'Clone',
        leading: Icon(AleraIcons.copy),
      ),
      if (automation.state == 'active')
        const AleraActionSheetEntry(
          value: _MoreAction.pauseAndCancel,
          label: 'Pause And Cancel Runs',
          leading: Icon(AleraIcons.stop),
          destructive: true,
        ),
      if (!automation.isTrashed)
        const AleraActionSheetEntry(
          value: _MoreAction.trash,
          label: 'Move To Trash',
          leading: Icon(AleraIcons.delete),
          destructive: true,
        ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _MoreAction.clone:
      await showMobileAutomationComposer(
        context,
        hostId: hostId,
        cloneOf: automation,
      );
    case _MoreAction.pauseAndCancel:
      await confirmMobileAutomationPauseAndCancel(context, actions, automation);
    case _MoreAction.trash:
      await confirmMobileAutomationTrash(context, actions, automation);
  }
}
