import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/automations/presentation/automations_dialog.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_providers.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:alera/src/features/workbench/presentation/quick_open_dialog.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

part 'workbench_dialog_launchers_create_workspace.dart';

/// Shared dialog flows for project/workspace creation and settings.
///
/// Extracted so both the sidebar controls and the keyboard command dispatcher
/// trigger the exact same behavior (dialogs, background job cards, toasts).

Future<void> openSettingsDialog(
  BuildContext context, {
  String initialSectionId = 'application',
  String? initialProjectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(
      initialSectionId: initialSectionId,
      initialProjectId: initialProjectId,
    ),
  );
}

Future<void> openAutomationsDialog(BuildContext context) {
  return showAutomationsDialog(context);
}

/// Opens Quick Open for the active workspace and restores the prior focus when
/// the modal route closes.
Future<void> showQuickOpenFlow(BuildContext context, WidgetRef ref) async {
  if (ref.read(workbenchControllerProvider).activeWorkspace == null) {
    return;
  }
  final previousFocus = FocusManager.instance.primaryFocus;
  await showDialog<void>(
    context: context,
    builder: (_) => const QuickOpenDialog(),
  );
  if (previousFocus?.canRequestFocus ?? false) {
    previousFocus!.requestFocus();
  }
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
Future<void> showAddProjectFlow(
  BuildContext context,
  WidgetRef ref, {
  ProjectCloneRequest? retryClone,
  String? retryError,
  String? retryJobId,
}) async {
  final jobs = ref.read(backgroundSetupJobsProvider.notifier);
  jobs.beginForm();
  late final AddProjectResult? result;
  try {
    result = await showDialog<AddProjectResult>(
      context: context,
      builder: (_) => AddProjectDialog(
        startOnClone: retryClone != null,
        initialGitUrl: retryClone?.gitUrl,
        initialDestinationPath: retryClone?.destinationPath,
        initialName: retryClone?.name,
        initialError: retryError,
      ),
    );
    if (result is CloneProjectResult) {
      unawaited(
        jobs.enqueueProjectClone(
          ProjectCloneRequest(
            gitUrl: result.gitUrl,
            destinationPath: result.destinationPath,
            name: result.name,
          ),
          jobId: retryJobId,
        ),
      );
    }
  } finally {
    jobs.endForm();
  }
  if (result == null) {
    return;
  }
  if (result case AddLocalProjectResult()) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      await controller.addLocalProject(path: result.path, name: result.name);
      AleraToast.publish(message: 'Project added', tone: .success);
    } catch (error) {
      AleraToast.publish(message: error.toString(), tone: .error);
    }
  }
}

class const _RenameDialog({
  required final String title,
  required final String labelText,
  required final String initialValue,
  required final String confirmLabel,
}) extends StatefulWidget {
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
          mainAxisSize: .min,
          crossAxisAlignment: .start,
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
              mainAxisAlignment: .end,
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
