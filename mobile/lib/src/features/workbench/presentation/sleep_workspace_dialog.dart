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
          'This closes all tabs and terminal sessions for "${workspace.name}". '
          'The workspace, branch, and files will be preserved.',
      confirmLabel: 'Sleep',
      destructive: true,
    ),
  );
  return confirmed == true;
}
