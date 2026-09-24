import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';

import '../../runtime/domain/workspace_relocation_recovery.dart';

Future<void> showWorkspaceRelocationRecoveryDialog({
  required BuildContext context,
  required Future<WorkspaceRelocationRecoverySnapshot> Function() load,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onResume,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onRunSetup,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onCancelSetup,
  Future<void> Function(WorkspaceRelocationRecoveryEntry)? onRecoverSetup,
}) => showDialog<void>(
  context: context,
  builder: (_) => _RecoveryDialog(
    load: load,
    onResume: onResume,
    onRunSetup: onRunSetup,
    onCancelSetup: onCancelSetup,
    onRecoverSetup: onRecoverSetup,
  ),
);

class const _RecoveryDialog({
  required final Future<WorkspaceRelocationRecoverySnapshot> Function() load,
  final Future<void> Function(WorkspaceRelocationRecoveryEntry)? onResume,
  final Future<void> Function(WorkspaceRelocationRecoveryEntry)? onRunSetup,
  final Future<void> Function(WorkspaceRelocationRecoveryEntry)? onCancelSetup,
  final Future<void> Function(WorkspaceRelocationRecoveryEntry)? onRecoverSetup,
}) extends StatefulWidget {
  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  WorkspaceRelocationRecoverySnapshot? _snapshot;
  Object? _error;
  bool _refreshFailed = false;
  bool _loading = true;
  bool _mutating = false;
  bool _canceling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _refreshFailed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _refreshFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<void> _perform(
    WorkspaceRelocationRecoveryEntry entry,
    Future<void> Function(WorkspaceRelocationRecoveryEntry) callback, {
    required String title,
    required String message,
    required String confirmLabel,
    bool cancellation = false,
  }) async {
    if (cancellation ? _canceling : _mutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _error = null;
      if (cancellation) {
        _canceling = true;
      } else {
        _mutating = true;
      }
    });
    try {
      await callback(entry);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          if (cancellation) {
            _canceling = false;
          } else {
            _mutating = false;
          }
        });
        await _load();
      }
    }
  }

  Widget _actions(WorkspaceRelocationRecoveryEntry entry) => Wrap(
    spacing: AleraTokens.space8,
    children: [
      if (!entry.completed && widget.onResume != null)
        TextButton(
          onPressed: _mutating
              ? null
              : () => _perform(
                  entry,
                  widget.onResume!,
                  title: 'Resume ${entry.action}?',
                  confirmLabel: 'Resume',
                  message:
                      'Resume transfer ${entry.id} with its original branch, folder and change choices. This can change files and the branch shared by other tasks. Buffers and processes will be checked again before continuing.',
                ),
          child: const Text('Resume'),
        ),
      if (entry.completed &&
          entry.hasSetupRecipe &&
          !entry.setupFinished &&
          entry.setupAttemptId == null &&
          widget.onRunSetup != null)
        TextButton(
          onPressed: _mutating
              ? null
              : () => _perform(
                  entry,
                  widget.onRunSetup!,
                  title: 'Run Saved Setup?',
                  confirmLabel: 'Run Setup',
                  message: 'Run the copy rules and commands saved for this transfer in its new worktree. The runtime will refuse if this setup was already attempted.',
                ),
          child: const Text('Run Setup'),
        ),
      if (entry.completed &&
          !entry.setupFinished &&
          entry.setupAttemptId != null) ...[
        if (widget.onCancelSetup != null)
          TextButton(
            onPressed: _canceling
                ? null
                : () => _perform(
                    entry,
                    widget.onCancelSetup!,
                    cancellation: true,
                    title: 'Cancel Setup?',
                    confirmLabel: 'Cancel Setup',
                    message:
                        'Request cancellation of setup attempt ${entry.setupAttemptId}. Its owner must verify process closure; this request alone does not confirm it.',
                  ),
            child: const Text('Cancel Setup'),
          ),
        if (widget.onRecoverSetup != null)
          TextButton(
            onPressed: _mutating
                ? null
                : () => _perform(
                    entry,
                    widget.onRecoverSetup!,
                    title: 'Recover Setup Outcome?',
                    confirmLabel: 'Recover Outcome',
                    message:
                        'Recover the recorded outcome for attempt ${entry.setupAttemptId}. The owner must verify its processes have closed. This does not repeat setup commands.',
                  ),
            child: const Text('Recover Outcome'),
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text(
              'Workspace Recovery',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            const Text(
              'Inspect saved transfers and setup outcomes. Opening this history does not resume a transfer or run setup.',
            ),
            const SizedBox(height: AleraTokens.space12),
            if (_loading || _mutating || _canceling)
              const LinearProgressIndicator(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AleraTokens.space12,
                        ),
                        child: Text(
                          'Recovery request failed: $_error${snapshot == null || !_refreshFailed ? '' : '\nPreviously loaded history is shown below.'}',
                        ),
                      ),
                    if (snapshot?.ownerError case final String error)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AleraTokens.space12,
                        ),
                        child: Text(
                          'Owner information is unavailable: $error\nSaved Home records remain available. Remote process closure has not been verified.',
                        ),
                      ),
                    if (snapshot != null && snapshot.entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: AleraTokens.space16,
                        ),
                        child: Text('No saved transfers for this task.'),
                      ),
                    for (final entry
                        in snapshot?.entries ??
                            const <WorkspaceRelocationRecoveryEntry>[]) ...[
                      const Divider(),
                      _RecoveryEntry(entry: entry),
                      if (entry.id == snapshot?.entries.firstOrNull?.id)
                        _actions(entry),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              mainAxisAlignment: .end,
              children: [
                TextButton(
                  onPressed: _loading ? null : _refresh,
                  child: const Text('Refresh'),
                ),
                const SizedBox(width: AleraTokens.space8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _RecoveryEntry({
  required final WorkspaceRelocationRecoveryEntry entry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          '${entry.action}: ${entry.completed ? 'completed' : 'pending'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text('Saved phase: ${_phaseLabel(entry.phase)}'),
        SelectableText('Transfer ID: ${entry.id}'),
        SelectableText('Original folder: ${entry.source.path}'),
        if (entry.destinationPath ?? entry.workspaceRoot case final String path)
          SelectableText(
            '${entry.destinationPath == null ? 'Worktree storage' : 'Destination'}: $path',
          ),
        if (entry.branch case final String branch) Text('Branch: $branch'),
        if (entry.replacementBranch case final String branch)
          Text('Replacement branch: $branch'),
        Text(
          entry.moveChanges
              ? 'Move all transferable changes.'
              : 'Leave uncommitted changes in the original folder.',
        ),
        if (entry.setupFinished)
          Text(
            entry.setupFailed
                ? 'Setup recorded failures.'
                : 'Setup outcome recorded.',
          ),
        if (!entry.setupFinished && entry.setupAttemptId != null)
          const Text(
            'Setup was attempted without a final recorded outcome. Verify its processes before recovery.',
          ),
        if (entry.setupCancellationRequested)
          const Text(
            'Setup cancellation was requested. This does not confirm process closure.',
          ),
        for (final observation in entry.processObservations) Text(observation),
      ],
    ),
  );
}

String _phaseLabel(String phase) => switch (phase) {
  'awaitingOwner' => 'awaiting owner information',
  'preparingDestination' => 'preparing destination',
  'destinationReady' => 'destination ready',
  'applyingChanges' => 'applying changes',
  'changesApplied' => 'changes applied',
  'removingSource' => 'removing previous worktree',
  _ => phase,
};
