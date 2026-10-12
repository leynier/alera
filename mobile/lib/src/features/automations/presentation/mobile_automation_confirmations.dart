import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:flutter/material.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: true,
      ),
    ) ==
    true;

/// Moving to Trash stops scheduling; the definition can still be restored.
Future<void> confirmMobileAutomationTrash(
  BuildContext context,
  MobileAutomationActions actions,
  AutomationRecord automation,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Move To Trash?',
    message:
        '"${automation.name}" stops scheduling and can be restored from Trash.',
    confirmLabel: 'Move To Trash',
  );
  if (confirmed) await actions.trash(automation);
}

/// Pausing normally lets active runs finish; this variant also cancels them.
Future<void> confirmMobileAutomationPauseAndCancel(
  BuildContext context,
  MobileAutomationActions actions,
  AutomationRecord automation,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Pause And Cancel Runs?',
    message:
        '"${automation.name}" stops scheduling and its active runs are asked to cancel. Their workspaces are kept.',
    confirmLabel: 'Pause And Cancel Runs',
  );
  if (confirmed) await actions.pause(automation, cancelRuns: true);
}

/// Whether the user agreed to forget the bound destination.
Future<bool> confirmMobileAutomationUnbind(BuildContext context) => _confirm(
  context,
  title: 'Unbind Workspace?',
  message: 'The next run creates a new workspace. The current one is kept.',
  confirmLabel: 'Unbind',
);

/// Whether the user agreed to leave the composer with unsaved changes.
Future<bool> confirmMobileAutomationDiscard(BuildContext context) => _confirm(
  context,
  title: 'Discard Changes?',
  message: 'Your changes to this automation are not saved.',
  confirmLabel: 'Discard Changes',
);
