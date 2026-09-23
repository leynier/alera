import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:flutter/material.dart';

Future<bool?> showProjectRemovalDialog(
  BuildContext context, {
  required String projectName,
  required ProjectRemovalPreview preview,
  required List<WorkspaceRemovalDependency> dependencies,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove Project'),
      content: SingleChildScrollView(
        child: Text(
          '$projectName\n\n'
          '${preview.workspaceCount} workspaces, '
          '${preview.tabCount} tabs, '
          '${preview.activeSessionCount} active sessions.\n\n'
          'Files and worktrees on the host will not be deleted.'
          '${dependencies.isEmpty ? '' : '\n\n${dependencies.map((dependency) => '${dependency.name}: ${dependency.activeRuns} active runs').join('\n')}\n\nContinuing pauses these automations when needed and cancels all of their active runs. History is preserved. Their targets must be changed before resuming.'}',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            dependencies.isEmpty ? 'Remove Project' : 'Pause And Remove',
          ),
        ),
      ],
    ),
  );
}
