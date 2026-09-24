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
          'This closes terminal sessions for "${workspace.name}". Tabs, '
          'branch, and files will be preserved, and agent sessions can '
          'resume when the workspace wakes.',
      confirmLabel: 'Sleep',
      destructive: true,
    ),
  );
  return confirmed == true;
}
