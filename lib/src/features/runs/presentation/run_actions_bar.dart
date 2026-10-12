import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pause or Resume, Open Workspace, Request Changes and Cancel Run.
class const RunActionsBar({super.key, required final RunSnapshot snapshot})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = snapshot.run;
    final actions = ref.watch(runActionsProvider);
    final key = RunActions.runKey(run.id);
    final busy = actions.busyFor(key);
    final error = actions.errorFor(key);
    final locked = busy != null;
    final reviewGateDue = snapshot.pendingGates.any(
      (gate) =>
          gate.actionable &&
          (gate.kind == RunGateKind.plan || gate.kind == RunGateKind.stage),
    );
    final cancelling = run.status == 'cancelled' && run.completedAt == null;
    final openWorkspace = runWorkspaceAction(
      context,
      ref,
      run.workspaceId,
      RunWorkspaceAction.workspace,
    );
    final canReplan =
        !run.finished &&
        run.planRevision != null &&
        const <String>{'running', 'paused'}.contains(run.status);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: <Widget>[
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            if (run.status == 'running')
              OutlinedButton(
                key: const ValueKey<String>('runPause'),
                onPressed: locked
                    ? null
                    : () => unawaited(
                        _control(context, ref, RunControlAction.pause),
                      ),
                child: Text(busy == 'pause' ? 'Pausing…' : 'Pause'),
              ),
            if (run.status == 'paused')
              OutlinedButton(
                key: const ValueKey<String>('runResume'),
                onPressed: locked || reviewGateDue
                    ? null
                    : () => unawaited(
                        _control(context, ref, RunControlAction.resume),
                      ),
                child: Text(busy == 'resume' ? 'Resuming…' : 'Resume'),
              ),
            OutlinedButton(
              key: const ValueKey<String>('runOpenWorkspace'),
              onPressed: openWorkspace,
              child: const Text('Open Workspace'),
            ),
            if (canReplan)
              OutlinedButton(
                key: const ValueKey<String>('runRequestChanges'),
                onPressed: locked
                    ? null
                    : () => unawaited(_requestChanges(context, ref)),
                child: Text(
                  busy == 'replan' ? 'Requesting Changes…' : 'Request Changes',
                ),
              ),
            if (cancelling && run.bucket == RunBucket.attention)
              OutlinedButton(
                key: const ValueKey<String>('runRetryCancellation'),
                onPressed: locked
                    ? null
                    : () => unawaited(
                        ref
                            .read(runActionsProvider.notifier)
                            .retryCancellation(snapshot),
                      ),
                child: Text(
                  busy == 'retryCancellation'
                      ? 'Retrying…'
                      : 'Retry Cancellation',
                ),
              ),
            if (!run.finished)
              TextButton(
                key: const ValueKey<String>('runCancel'),
                style: TextButton.styleFrom(foregroundColor: AleraTokens.error),
                onPressed: locked
                    ? null
                    : () => unawaited(confirmCancelRun(context, ref, snapshot)),
                child: Text(busy == 'cancel' ? 'Cancelling…' : 'Cancel Run'),
              ),
          ],
        ),
        if (reviewGateDue && run.status == 'paused')
          Text(
            'Resolve the pending gate above to resume.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        if (error != null)
          AleraInlineNotice(tone: .error, message: runErrorMessage(error)),
      ],
    );
  }

  Future<void> _control(
    BuildContext context,
    WidgetRef ref,
    RunControlAction action, {
    String? reason,
  }) async {
    final receipt = await ref
        .read(runActionsProvider.notifier)
        .control(snapshot, action, reason: reason);
    if (receipt == null || !context.mounted) return;
    AleraToast.show(
      context,
      message: switch (action) {
        RunControlAction.pause => 'Run paused',
        RunControlAction.resume => 'Run resumed',
        RunControlAction.cancel => 'Run cancelled',
        RunControlAction.replan => 'Changes requested',
      },
      tone: AleraToastTone.success,
    );
  }

  Future<void> _requestChanges(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RequestChangesDialog(),
    );
    if (reason == null || !context.mounted) return;
    await _control(context, ref, RunControlAction.replan, reason: reason);
  }
}

/// Asks before cancelling: the runtime stops every worker of the run.
Future<void> confirmCancelRun(
  BuildContext context,
  WidgetRef ref,
  RunSnapshot snapshot,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const AleraConfirmDialog(
      title: 'Cancel Run?',
      message: 'Every worker of this run stops and pending gates close. Retained worktrees and branches stay until you clean up.',
      confirmLabel: 'Cancel Run',
      cancelLabel: 'Keep Running',
      destructive: true,
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final receipt = await ref
      .read(runActionsProvider.notifier)
      .control(snapshot, RunControlAction.cancel);
  if (receipt != null && context.mounted) {
    AleraToast.show(
      context,
      message: 'Run cancelled',
      tone: AleraToastTone.success,
    );
  }
}

class const _RequestChangesDialog() extends StatefulWidget {
  @override
  State<_RequestChangesDialog> createState() => _RequestChangesDialogState();
}

class _RequestChangesDialogState extends State<_RequestChangesDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isNotEmpty) Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => AleraDialog(
    maxWidth: AleraTokens.dialogWideWidth,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space12,
        children: <Widget>[
          AleraDialogHeader(
            title: 'Request Changes',
            onClose: () => Navigator.of(context).pop(),
          ),
          Text(
            'The coordinator receives your notes and proposes a new plan. Completed work is kept.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          AleraTextField(
            key: const ValueKey<String>('runChangesReason'),
            controller: _reason,
            labelText: 'Notes',
            hintText: 'What should change?',
            minLines: 3,
            maxLines: 8,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onCommandEnter: _submit,
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: AleraTokens.space8,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey<String>('runChangesSubmit'),
                onPressed: _reason.text.trim().isEmpty ? null : _submit,
                child: const Text('Request Changes'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
