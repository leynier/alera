import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared dialog flows for project/workspace creation and settings.
///
/// Extracted so both the sidebar controls and the keyboard command dispatcher
/// trigger the exact same behavior (dialogs, clone progress, toasts).

Future<void> openSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const SettingsDialog(),
  );
}

Future<String?> showRenameDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  required String initialValue,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(
      title: title,
      labelText: labelText,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
}

/// Opens the add-project dialog and runs the chosen local-folder or clone flow.
Future<void> showAddProjectFlow(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<AddProjectResult>(
    context: context,
    builder: (_) => const AddProjectDialog(),
  );
  if (result == null || !context.mounted) {
    return;
  }
  final controller = ref.read(workbenchControllerProvider.notifier);
  try {
    switch (result) {
      case AddLocalProjectResult():
        await controller.addLocalProject(path: result.path, name: result.name);
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project added',
          tone: AleraToastTone.success,
        );
      case CloneProjectResult():
        await _runWithProgress(
          context,
          message: 'Cloning repository…',
          action: () => controller.cloneProject(
            gitUrl: result.gitUrl,
            destinationPath: result.destinationPath,
            name: result.name,
          ),
        );
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project cloned',
          tone: AleraToastTone.success,
        );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: error.toString(),
      tone: AleraToastTone.error,
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String labelText;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialValue.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = '${widget.labelText} is required');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              labelText: widget.labelText,
              errorText: _errorText,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the create-workspace dialog for the active Git project. Linked
/// workspaces require a Git project, so folder-only projects are filtered out.
Future<void> showCreateWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  Project? initialProject,
}) async {
  final controller = ref.read(workbenchControllerProvider.notifier);
  final projects = ref
      .read(workbenchControllerProvider)
      .projects
      .where((project) => project.supportsLinkedWorkspaces)
      .toList(growable: false);
  if (projects.isEmpty) {
    AleraToast.show(
      context,
      message: 'Linked workspaces require a Git project.',
      tone: AleraToastTone.info,
    );
    return;
  }
  final resolvedInitialProject =
      initialProject?.supportsLinkedWorkspaces == true ? initialProject : null;

  final result = await showDialog<CreateWorkspaceResult>(
    context: context,
    builder: (_) => CreateWorkspaceDialog(
      projects: projects,
      initialProject: resolvedInitialProject,
      loadBranches: controller.listSourceBranches,
    ),
  );
  if (result == null || !context.mounted) {
    return;
  }
  try {
    await controller.createWorkspace(
      project: result.project,
      sourceBranch: result.sourceBranch,
      newBranchName: result.newBranchName,
      name: result.name,
    );
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Workspace created',
      tone: AleraToastTone.success,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: error.toString(),
      tone: AleraToastTone.error,
    );
  }
}

Future<T> _runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
}) async {
  var progressOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProjectProgressDialog(message: message),
    ).whenComplete(() => progressOpen = false),
  );
  await Future<void>.delayed(Duration.zero);
  try {
    return await action();
  } finally {
    if (context.mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
