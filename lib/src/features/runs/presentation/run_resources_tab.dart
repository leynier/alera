import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/runs/application/run_cleanup_session.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/infra/run_watch.dart';
import 'package:alera/src/features/runs/presentation/run_cleanup_review.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_resources_selection.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cleanup as an action of an isolated run: select resources, review the
/// preview, apply it, and retry or abandon a cleanup that needs attention.
/// Durable confirmations and receipts live in the runtime.
class RunResourcesTab extends ConsumerStatefulWidget {
  const RunResourcesTab({super.key, required this.snapshot});

  final RunSnapshot snapshot;

  @override
  ConsumerState<RunResourcesTab> createState() => _RunResourcesTabState();
}

class _RunResourcesTabState extends ConsumerState<RunResourcesTab> {
  late final RunCleanupSession _session;
  late final StreamSubscription<void> _watch;

  @override
  void initState() {
    super.initState();
    final runId = widget.snapshot.run.id;
    _session = RunCleanupSession(ref.read(runRepositoryProvider), runId)
      ..addListener(_changed);
    _watch = watchRuns<void>(
      client: ref.read(runtimeHostClientProvider),
      coalescer: ref.read(runtimeChangeCoalescerProvider),
      key: 'runs-cleanup:$runId',
      read: _session.refresh,
    ).listen((_) {}, onError: _session.reportError);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _openWorkspace(String id) {
    final action = runWorkspaceAction(
      context,
      ref,
      id,
      RunWorkspaceAction.workspace,
      listen: false,
    );
    if (action == null) {
      _session.reportError(
        StateError('This workspace is unavailable. Refresh its cleanup.'),
      );
    } else {
      action();
    }
  }

  Future<void> _retry(String id) async {
    await _session.open(id);
    await _session.apply(true);
  }

  Future<void> _abandon(String id) async {
    await _session.open(id);
    await _session.abandon();
  }

  @override
  void dispose() {
    unawaited(_watch.cancel());
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.snapshot.run;
    final status = _session.status;
    if (_session.error is RunsUpdateRequired) {
      return RunReadState(
        error: _session.error,
        subject: 'resources',
        onRefresh: _session.refresh,
      );
    }
    if (_session.selectedId != null && status == null) {
      return ListView(
        padding: const EdgeInsets.all(AleraTokens.space16),
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _session.open(null),
              child: const Text('Back To Resources'),
            ),
          ),
          Text(
            _session.error == null
                ? 'Loading the cleanup…'
                : runErrorMessage(_session.error!),
          ),
        ],
      );
    }
    if (status != null) {
      return RunCleanupReviewPanel(
        status: status,
        now: ref.watch(runClockProvider)(),
        busy: _session.busy,
        error: _session.error,
        onBack: () => _session.open(null),
        onRefresh: _session.refresh,
        onApply: _session.apply,
        onAbandon: _session.abandon,
        abandonPending: _session.abandonPending,
        onOpenWorkspace: _openWorkspace,
      );
    }
    return RunResourcesSelection(
      session: _session,
      allowPrepare: run.finished && run.completedAt != null,
      onOpen: _session.open,
      onWorkspace: _openWorkspace,
      onRetry: (id) => unawaited(_retry(id)),
      onAbandon: (id) => unawaited(_abandon(id)),
    );
  }
}
