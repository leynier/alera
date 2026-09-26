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
  bool _confirmCancel = false;
  bool _cancelRequested = false;
  int _generation = 0;
  int? _retrySequence;

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
    if (_busy || _cancelRequested || _status?['cancellation'] != null) return;
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

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = true;
      _error = null;
    });
    try {
      await _repository.cancelProposal(widget.id);
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryCancellation() async {
    if (_busy) return;
    final cancellation = _status?['cancellation'] as Map?;
    final sequence = _retrySequence ?? cancellation?['sequence'];
    if (sequence is! int || sequence < 0) return;
    setState(() {
      _busy = true;
      _retrySequence = sequence;
      _error = null;
    });
    try {
      final receipt = await _repository.retryProposalCancellation(
        widget.id,
        sequence,
      );
      if (!mounted) return;
      setState(() {
        _status = {...?_status, 'cancellation': receipt};
        _retrySequence = null;
      });
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
    final cancellation = _status?['cancellation'] as Map?;
    final cancelState = cancellation?['status'] as String?;
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
          cancelState == 'settled'
              ? 'Proposal Cancelled'
              : cancelState == 'pending'
              ? 'Cancelling Proposal'
              : cancelState == 'attention'
              ? 'Cancellation Needs Attention'
              : run != null
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
          cancelState == 'settled'
              ? 'The proposal is cancelled. Its selection and history are retained; it cannot launch a coordinator or submit a plan.'
              : cancelState == 'pending'
              ? 'Cancellation is saved. The runtime is stopping the coordinator; its process has not yet been confirmed stopped.'
              : cancelState == 'attention'
              ? 'The runtime could not confirm that the coordinator stopped. Inspect the retained terminal, then retry cancellation. The cancelled proposal cannot submit a plan.'
              : run != null
              ? 'The coordinator submitted a plan. Open the run to review its revision before starting any workers.'
              : state == 'started'
              ? 'The coordinator is preparing the task plan. Workers have not been started by this proposal.'
              : state == 'reserved'
              ? 'The coordinator launch is reserved. Refresh or inspect the terminal; repeating the request will not start another coordinator.'
              : state == 'attention'
              ? 'Coordinator launch needs inspection. Its receipt is retained to prevent duplicate launches.'
              : 'The selection is saved. Start the coordinator to propose a concrete plan.',
        ),
        if (cancellation?['error'] case final String error)
          SelectableText(error),
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
            if (_retrySequence != null ||
                (cancelState == 'attention' &&
                    cancellation?['sequence'] is int))
              OutlinedButton(
                onPressed: _busy ? null : _retryCancellation,
                child: const Text('Retry Cancellation'),
              ),
            if (run != null)
              FilledButton(
                onPressed: () => widget.onOpenRun(run),
                child: const Text('Open Prepared Run'),
              ),
            if (_status != null &&
                coordinator == null &&
                run == null &&
                cancellation == null &&
                !_cancelRequested)
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
            if (_status != null &&
                run == null &&
                cancellation == null &&
                !_confirmCancel)
              TextButton(
                onPressed: _busy || _error != null
                    ? null
                    : () => setState(() => _confirmCancel = true),
                child: const Text('Cancel Proposal'),
              ),
          ],
        ),
        if (_confirmCancel && run == null && cancellation == null) ...[
          const SizedBox(height: AleraTokens.space12),
          const Text(
            'Cancel this proposal and stop its coordinator. The saved selection and source changes are retained. This does not cancel any other run.',
          ),
          if (_cancelRequested)
            const Text(
              'If the response was lost, retry sends cancellation for the same proposal.',
            ),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: Text(
                  _cancelRequested
                      ? 'Retry Cancellation'
                      : 'Confirm Cancellation',
                ),
              ),
              if (!_cancelRequested)
                TextButton(
                  autofocus: true,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _confirmCancel = false),
                  child: const Text('Keep Proposal'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
