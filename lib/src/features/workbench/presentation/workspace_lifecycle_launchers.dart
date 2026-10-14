import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirms, then sleeps [workspace]: its terminal sessions close while tabs,
/// branch, and files stay. Shared by the sidebar and the details card. The
/// result is published rather than shown from [context], because sleeping the
/// open workspace closes the card that asked for it.
Future<void> showSleepWorkspaceFlow(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
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
  if (confirmed != true || !context.mounted) {
    return;
  }
  final controller = ref.read(workbenchControllerProvider.notifier);
  final runtime = ref.read(terminalRuntimeProvider);
  try {
    await controller.sleepWorkspace(workspace);
    // The controller releases the live handles; keep this call so sleep
    // still drops them when the controller is stubbed. Double close is
    // idempotent.
    runtime.closeWorkspace(workspace.id);
    AleraToast.publish(message: 'Workspace slept', tone: .success);
  } catch (error) {
    AleraToast.publish(
      message: 'Could not sleep workspace: $error',
      tone: .error,
    );
  }
}

/// Archives [workspace] after confirming, or unarchives it right away.
Future<void> showToggleWorkspaceArchivedFlow(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final controller = ref.read(workbenchControllerProvider.notifier);
  if (workspace.isArchived) {
    try {
      await controller.unarchiveWorkspace(workspace);
      AleraToast.publish(message: 'Workspace unarchived', tone: .success);
    } catch (error) {
      AleraToast.publish(
        message: 'Could not unarchive workspace: $error',
        tone: .error,
      );
    }
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AleraConfirmDialog(
      title: 'Archive Workspace?',
      message:
          'This closes terminal sessions for "${workspace.name}" and hides '
          'it from the sidebar. Tabs, branch, and files will be preserved, '
          'and agent sessions can resume when it is unarchived.',
      confirmLabel: 'Archive',
      destructive: true,
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await controller.archiveWorkspace(workspace);
    AleraToast.publish(message: 'Workspace archived', tone: .success);
  } catch (error) {
    AleraToast.publish(
      message: 'Could not archive workspace: $error',
      tone: .error,
    );
  }
}
