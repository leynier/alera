import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_workspace_actions.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _ProposalRead = (int, Map<String, Object?>?, Object?);

class WorkflowProposalPage extends ConsumerStatefulWidget {
  const WorkflowProposalPage({
    super.key,
    required this.id,
    required this.onBack,
    required this.onOpenRun,
  });
  final String id;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenRun;
  @override
  ConsumerState<WorkflowProposalPage> createState() =>
      _WorkflowProposalPageState();
}

class _WorkflowProposalPageState extends ConsumerState<WorkflowProposalPage> {
  late final WorkflowLifecycleRepository _repository;
  StreamSubscription<_ProposalRead>? _watch;
  Map<String, Object?>? _status;
  Object? _error;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(workflowLifecycleRepositoryProvider);
    final client = _repository.client;
    _watch =
        watchRunBoard<_ProposalRead>(
          client: client,
          coalescer: ref.read(runtimeChangeCoalescerProvider),
          key: 'workflow-proposal:${widget.id}',
          read: _readStatus,
        ).listen(
          _acceptStatus,
          onError: (Object error) {
            if (mounted) {
              _generation++;
              setState(() => _error = error);
            }
          },
        );
  }

  Future<_ProposalRead> _readStatus() async {
    final generation = ++_generation;
    try {
      return (generation, await _repository.proposalStatus(widget.id), null);
    } on Object catch (error) {
      return (generation, null, error);
    }
  }

  void _acceptStatus(_ProposalRead result) {
    if (!mounted || result.$1 != _generation) return;
    setState(() {
      if (result.$2 != null) _status = result.$2;
      _error = result.$3;
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      _acceptStatus(await _readStatus());
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _repository.startCoordinator(widget.id);
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = _status?['coordinator'] as Map?;
    final run = _status?['runId'] as String?;
    final state = coordinator?['status'] as String?;
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onBack,
            child: const Text('Back To Runs'),
          ),
        ),
        Text(
          run != null
              ? 'Plan Prepared'
              : state == 'attention'
              ? 'Proposal Needs Attention'
              : 'Workflow Proposal',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AleraTokens.space12),
        SelectableText(widget.id, style: AleraTokens.monoCompactStyle),
        const SizedBox(height: AleraTokens.space12),
        Text(
          run != null
              ? 'The coordinator submitted a plan. Open the run to review its revision before starting any workers.'
              : state == 'started'
              ? 'The coordinator is preparing the task plan. Workers have not been started by this proposal.'
              : state == 'reserved'
              ? 'The coordinator launch is reserved. Refresh or inspect the terminal; repeating the request will not start another coordinator.'
              : state == 'attention'
              ? 'Coordinator launch needs inspection. Its receipt is retained to prevent duplicate launches.'
              : 'The selection is saved. Start the coordinator to propose a concrete plan.',
        ),
        if (coordinator?['error'] case final String error) ...[
          const SizedBox(height: AleraTokens.space12),
          SelectableText(error),
        ],
        if (_error != null) ...[
          const SizedBox(height: AleraTokens.space12),
          SelectableText(_error.toString()),
        ],
        const SizedBox(height: AleraTokens.space16),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            if (run != null)
              FilledButton(
                onPressed: () => widget.onOpenRun(run),
                child: const Text('Open Prepared Run'),
              ),
            if (_status != null && coordinator == null && run == null)
              FilledButton(
                onPressed: _busy || _error != null ? null : _start,
                child: const Text('Start Coordinator'),
              ),
            if (coordinator != null)
              OutlinedButton(
                onPressed: runBoardWorkspaceAction(
                  context,
                  ref,
                  coordinator['workspaceId']! as String,
                  RunBoardWorkspaceAction.terminal,
                  terminalHandle: coordinator['tabId']! as String,
                ),
                child: const Text('Open Coordinator Terminal'),
              ),
            OutlinedButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('Refresh Proposal'),
            ),
          ],
        ),
      ],
    );
  }
}
