import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';

Future<bool> showSleepWorkspaceDialog(
  BuildContext context, {
  required WorkspaceSummary workspace,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sleep Workspace?'),
      content: Text(
        'This Closes All Tabs And Terminal Sessions For "${workspace.name}". '
        'The Workspace, Branch, And Files Will Be Preserved.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sleep'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
