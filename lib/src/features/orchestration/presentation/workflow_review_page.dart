import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/workflow_review_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_review_panel.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowReviewPage extends ConsumerStatefulWidget {
  const WorkflowReviewPage({
    super.key,
    required this.runId,
    required this.revision,
    required this.scope,
    required this.onBack,
    required this.onInspectTask,
  });
  final String runId;
  final int revision;
  final String scope;
  final VoidCallback onBack;
  final ValueChanged<String> onInspectTask;

  @override
  ConsumerState<WorkflowReviewPage> createState() => _WorkflowReviewPageState();
}

class _WorkflowReviewPageState extends ConsumerState<WorkflowReviewPage> {
  late final WorkflowLifecycleRepository _repository;
  StreamSubscription<RuntimeHostEvent>? _events;
  Timer? _expiry;
  WorkflowReviewSnapshot? _review;
  WorkflowPendingDecision? _pending;
  Object? _error;
  bool _busy = true;
  bool _invalidated = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final client = ref.read(runtimeHostClientProvider);
    _repository = WorkflowLifecycleRepository(client, client);
    _events = client.runtimeEvents.listen(
      (event) {
        if ({
          aleraRuntimeHostDisconnectedEvent,
          aleraRuntimeHostConnectedEvent,
          'orchestrationBoardChanged',
          'workspacesChanged',
        }.contains(event.name)) {
          _invalidate();
        }
      },
      onError: (Object _) => _invalidate(),
      onDone: _invalidate,
    );
    unawaited(_load());
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    if (_review != null) setState(() => _invalidated = true);
  }

  @override
  void didUpdateWidget(WorkflowReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _invalidate();
  }

  Future<void> _load() async {
    if (_pending != null) return;
    _expiry?.cancel();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final review = await _repository.review(
        widget.runId,
        widget.revision,
        widget.scope,
      );
      if (!mounted) return;
      if (generation != _generation) {
        throw StateError(
          'The runtime changed while loading. Refresh the review.',
        );
      }
      final remaining = review.expiresAt.difference(DateTime.now());
      setState(() {
        _review = review;
        _invalidated = remaining <= Duration.zero;
      });
      if (remaining > Duration.zero) _expiry = Timer(remaining, _invalidate);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _invalidated = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(WorkflowHumanDecision decision, String reason) async {
    if (_busy || _invalidated || _review == null || _pending != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final generation = _generation;
    try {
      final pending = await _repository.prepareDecision(
        _review!,
        decision,
        reason,
      );
      if (!mounted) return;
      if (generation != _generation) {
        throw StateError(
          'The review changed before submission. Refresh and review again.',
        );
      }
      _pending = pending;
      await _submit();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final pending = _pending;
    if (pending == null) return;
    await _repository.submitDecision(pending);
    if (!mounted) return;
    _pending = null;
    widget.onBack();
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _submit();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    if (review == null) {
      return ListView(
        padding: const EdgeInsets.all(AleraTokens.space16),
        children: [
          TextButton(
            onPressed: widget.onBack,
            child: const Text('Back To Run'),
          ),
          Text(
            _error is WorkflowLifecycleUpdateRequired
                ? 'Update Required'
                : _busy
                ? 'Loading Review'
                : 'Review Unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_error != null) ...[
            SelectableText(_error.toString()),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh Review'),
            ),
          ],
        ],
      );
    }
    return Column(
      children: [
        if (_pending != null && !_busy)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              children: [
                const Text(
                  'The decision response was not received. Retry the same signed decision or return to inspect the current run.',
                ),
                OutlinedButton(
                  onPressed: _retry,
                  child: const Text('Retry Decision'),
                ),
              ],
            ),
          ),
        Expanded(
          child: WorkflowReviewPanel(
            review: review,
            busy: _busy,
            invalidated: _invalidated || _pending != null,
            error: _error?.toString(),
            onBack: widget.onBack,
            onRefresh: _pending == null ? _load : null,
            onInspectTask: widget.onInspectTask,
            onDecision: (decision, reason) =>
                unawaited(_decide(decision, reason)),
          ),
        ),
      ],
    );
  }
}
