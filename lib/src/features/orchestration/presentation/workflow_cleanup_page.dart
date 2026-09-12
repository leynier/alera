import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/workflow_cleanup_session.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_workspace_actions.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_review_panel.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_cleanup_selection_panel.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowCleanupPage extends ConsumerStatefulWidget {
  const WorkflowCleanupPage({
    super.key,
    required this.runId,
    required this.allowPrepare,
    required this.onBack,
    required this.onSelected,
    this.initialCleanupId,
  });
  final String runId;
  final bool allowPrepare;
  final String? initialCleanupId;
  final VoidCallback onBack;
  final ValueChanged<String?> onSelected;
  @override
  ConsumerState<WorkflowCleanupPage> createState() =>
      _WorkflowCleanupPageState();
}

class _WorkflowCleanupPageState extends ConsumerState<WorkflowCleanupPage> {
  late final WorkflowCleanupSession _session;
  late final StreamSubscription<void> _watch;
  String? _reportedId;
  @override
  void initState() {
    super.initState();
    final lifecycle = ref.read(workflowLifecycleRepositoryProvider);
    _reportedId = widget.initialCleanupId;
    _session = WorkflowCleanupSession(
      WorkflowCleanupRepository(lifecycle),
      widget.runId,
      cleanupId: widget.initialCleanupId,
    )..addListener(_changed);
    _watch = watchRunBoard<void>(
      client: lifecycle.client,
      coalescer: ref.read(runtimeChangeCoalescerProvider),
      key: 'workflow-cleanup:${widget.runId}',
      read: _session.refresh,
    ).listen((_) {}, onError: _session.reportError);
  }

  void _changed() {
    if (!mounted) return;
    if (_reportedId != _session.selectedId) {
      _reportedId = _session.selectedId;
      widget.onSelected(_reportedId);
    }
    setState(() {});
  }

  void _openWorkspace(String id) {
    final action = runBoardWorkspaceAction(
      context,
      ref,
      id,
      RunBoardWorkspaceAction.workspace,
      listen: false,
    );
    if (action == null) {
      _session.reportError(
        StateError(
          'This workspace is unavailable. Refresh its cleanup status.',
        ),
      );
    } else {
      action();
    }
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
    final status = _session.status;
    if (_session.error is WorkflowLifecycleUpdateRequired ||
        (_session.selectedId != null && status == null)) {
      return ListView(
        padding: const EdgeInsets.all(AleraTokens.space16),
        children: [
          TextButton(
            onPressed: _session.error is WorkflowLifecycleUpdateRequired
                ? widget.onBack
                : () => _session.open(null),
            child: Text(
              _session.error is WorkflowLifecycleUpdateRequired
                  ? 'Back To Run'
                  : 'Back To Resources',
            ),
          ),
          Text(
            _session.error is WorkflowLifecycleUpdateRequired
                ? 'Update Required'
                : 'Cleanup Status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(_session.error?.toString() ?? 'Loading the saved cleanup...'),
          TextButton(
            onPressed: _session.refresh,
            child: const Text('Refresh Status'),
          ),
        ],
      );
    }
    if (status != null) {
      return WorkflowCleanupReviewPanel(
        status: status,
        now: DateTime.now(),
        busy: _session.busy,
        error: _session.error,
        onBack: () => _session.open(null),
        onRefresh: _session.refresh,
        onApply: _session.apply,
        onOpenWorkspace: _openWorkspace,
      );
    }
    return WorkflowCleanupSelectionPanel(
      session: _session,
      allowPrepare: widget.allowPrepare,
      onBack: widget.onBack,
      onOpen: _session.open,
      onWorkspace: _openWorkspace,
    );
  }
}
