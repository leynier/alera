import 'dart:async';

import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_actions.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/infra/mobile_runtime_run_repository.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_resources_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Actions of a run, in the order the overflow sheet lists them.
enum RunMenuAction {
  openWorkspace('Open Workspace'),
  cleanUp('Clean Up Resources'),
  pause('Pause'),
  resume('Resume'),
  requestChanges('Request Changes'),
  retryCancellation('Retry Cancellation'),
  cancel('Cancel Run');

  RunMenuAction(this.label);

  final String label;
}

/// What a person can do with [detail] right now.
List<RunMenuAction> availableRunActions(RunDetail detail) {
  final run = detail.run;
  final open = !run.isFinished && !run.isCancelling;
  return <RunMenuAction>[
    if (run.workspaceId.isNotEmpty) RunMenuAction.openWorkspace,
    if (run.isolation == RunIsolation.isolated && run.isFinished)
      RunMenuAction.cleanUp,
    if (run.status == 'running') RunMenuAction.pause,
    if (run.status == 'paused') RunMenuAction.resume,
    if (open && run.status != 'planning') RunMenuAction.requestChanges,
    if (run.isCancelling) RunMenuAction.retryCancellation,
    if (open) RunMenuAction.cancel,
  ];
}

IconData _icon(RunMenuAction action) => switch (action) {
  RunMenuAction.openWorkspace => AleraIcons.workspaces,
  RunMenuAction.cleanUp => AleraIcons.delete,
  RunMenuAction.pause => AleraIcons.stop,
  RunMenuAction.resume => AleraIcons.restore,
  RunMenuAction.requestChanges => AleraIcons.edit,
  RunMenuAction.retryCancellation => AleraIcons.refresh,
  RunMenuAction.cancel => AleraIcons.cancel,
};

/// The overflow of the run detail screen.
Future<void> showRunActions(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required RunDetail detail,
}) async {
  final action = await showAleraActionSheet<RunMenuAction>(
    context,
    entries: <AleraActionSheetEntry<RunMenuAction>>[
      for (final action in availableRunActions(detail))
        AleraActionSheetEntry<RunMenuAction>(
          value: action,
          label: action.label,
          leading: Icon(_icon(action)),
          destructive: action == RunMenuAction.cancel,
          trailing: switch ((action, detail.resourceCount)) {
            (RunMenuAction.cleanUp, final count?) when count > 0 => AleraBadge(
              key: const ValueKey<String>('run-resource-count'),
              label: '$count',
            ),
            _ => null,
          },
        ),
    ],
  );
  if (action == null || !context.mounted) return;
  await performRunAction(
    context,
    ref,
    hostId: hostId,
    detail: detail,
    action: action,
  );
}

Future<void> performRunAction(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required RunDetail detail,
  required RunMenuAction action,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final actions = ref.read(
    mobileRunActionsProvider(hostId, detail.run.id).notifier,
  );
  try {
    switch (action) {
      case RunMenuAction.openWorkspace:
        await _openWorkspace(context, ref, hostId, detail.run.workspaceId);
      case RunMenuAction.cleanUp:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                RunResourcesScreen(hostId: hostId, runId: detail.run.id),
          ),
        );
      case RunMenuAction.pause || RunMenuAction.resume:
        await actions.control(
          action == RunMenuAction.pause
              ? RunControlAction.pause
              : RunControlAction.resume,
          expectedSequence: detail.controlSequence,
        );
      case RunMenuAction.requestChanges:
        final reason = await showDialog<String>(
          context: context,
          builder: (_) => const AleraRenameDialog(
            title: 'Request Changes',
            labelText: 'What should change?',
            helperText:
                'The coordinator receives this note and proposes a new plan.',
            confirmLabel: 'Request Changes',
          ),
        );
        if (reason == null || reason.trim().isEmpty) return;
        await actions.control(
          RunControlAction.replan,
          expectedSequence: detail.controlSequence,
          reason: reason,
        );
      case RunMenuAction.retryCancellation:
        await actions.retryCancellation(
          expectedSequence: detail.controlSequence,
        );
      case RunMenuAction.cancel:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => const AleraConfirmDialog(
            title: 'Cancel Run',
            message: 'Workers stop and unfinished tasks are cancelled. Retained worktrees and branches stay until you clean up.',
            confirmLabel: 'Cancel Run',
            cancelLabel: 'Keep Run',
            destructive: true,
          ),
        );
        if (confirmed != true) return;
        await actions.control(
          RunControlAction.cancel,
          expectedSequence: detail.controlSequence,
        );
    }
  } on Object catch (error, stackTrace) {
    showActionFailure(
      messenger,
      action: 'change the run',
      error: error,
      stackTrace: stackTrace,
      message: runErrorMessage(error),
    );
  }
}

Future<void> _openWorkspace(
  BuildContext context,
  WidgetRef ref,
  String hostId,
  String workspaceId,
) async {
  final repository = await ref.read(mobileRunRepositoryProvider(hostId).future);
  final workspaces = await repository.workspaces();
  final workspace = workspaces
      .where((item) => item.id == workspaceId)
      .firstOrNull;
  if (!context.mounted) return;
  if (workspace == null) {
    throw StateError('The workspace is no longer available.');
  }
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            WorkspaceTabsScreen(hostId: hostId, workspace: workspace),
      ),
    ),
  );
}
