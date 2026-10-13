import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: destructive,
      ),
    ) ==
    true;

/// Moving to Trash stops scheduling; the definition can still be restored.
Future<void> confirmAutomationTrash(
  BuildContext context,
  WidgetRef ref,
  AutomationRecord automation,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Move To Trash?',
    message:
        '"${automation.name}" stops scheduling and can be restored from Trash.',
    confirmLabel: 'Move To Trash',
  );
  if (confirmed) await AutomationActions(ref).trash(automation);
}

/// Pausing normally lets active runs finish; this variant also cancels them.
Future<void> confirmAutomationPauseAndCancel(
  BuildContext context,
  WidgetRef ref,
  AutomationRecord automation,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Pause And Cancel Runs?',
    message:
        '"${automation.name}" stops scheduling and its active runs are asked to cancel. Their workspaces are kept.',
    confirmLabel: 'Pause And Cancel Runs',
  );
  if (confirmed) {
    await AutomationActions(ref).pause(automation, cancelRuns: true);
  }
}

/// Whether the user agreed to forget the bound destination.
Future<bool> confirmAutomationUnbind(BuildContext context) => _confirm(
  context,
  title: 'Unbind Workspace?',
  message: 'The next run creates a new workspace. The current one is kept.',
  confirmLabel: 'Unbind',
);

/// Whether the user agreed to close an editor with unsaved changes.
Future<bool> confirmAutomationDiscard(BuildContext context) => _confirm(
  context,
  title: 'Discard Changes?',
  message: 'Your changes to this automation are not saved.',
  confirmLabel: 'Discard Changes',
);
