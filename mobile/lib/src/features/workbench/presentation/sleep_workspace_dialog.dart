import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';

Future<bool> showSleepWorkspaceDialog(
  BuildContext context, {
  required WorkspaceSummary workspace,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AleraConfirmDialog(
      title: 'Sleep Workspace?',
      message:
          'This Closes All Tabs And Terminal Sessions For "${workspace.name}". '
          'The Workspace, Branch, And Files Will Be Preserved.',
      confirmLabel: 'Sleep',
      destructive: true,
    ),
  );
  return confirmed == true;
}
