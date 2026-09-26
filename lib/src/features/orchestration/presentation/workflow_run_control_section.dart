import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_panel.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

typedef _ControlRead = (int, WorkflowRunControls?, Object?);

class WorkflowRunControlSection extends ConsumerStatefulWidget {
  const WorkflowRunControlSection({
    super.key,
    required this.runId,
    required this.revision,
    required this.onReview,
    this.onCorrection,
  });
  final String runId;
  final int revision;
  final ValueChanged<String> onReview;
  final VoidCallback? onCorrection;
  @override
  ConsumerState<WorkflowRunControlSection> createState() =>
      _WorkflowRunControlSectionState();
}

class _WorkflowRunControlSectionState
    extends ConsumerState<WorkflowRunControlSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final WorkflowLifecycleRepository _repository;
  StreamSubscription<_ControlRead>? _watch;
  WorkflowRunControls? _controls;
  Object? _error;
  String? _pending;
  String? _pendingAction;
  int? _pendingSequence;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(workflowLifecycleRepositoryProvider);
    _watch =
        watchRunBoard<_ControlRead>(
          client: _repository.client,
          coalescer: ref.read(runtimeChangeCoalescerProvider),
          key: 'workflow-controls:${widget.runId}:${widget.revision}',
          read: _read,
        ).listen(
          _accept,
          onError: (Object error) {
            if (mounted) {
              _generation++;
              setState(() => _error = error);
            }
          },
        );
  }

  Future<_ControlRead> _read() async {
    final generation = ++_generation;
    try {
      return (
        generation,
        await _repository.controls(widget.runId, widget.revision),
        null,
      );
    } on Object catch (error) {
      return (generation, null, error);
    }
  }

  void _accept(_ControlRead result) {
    if (!mounted || result.$1 != _generation) return;
    setState(() {
      if (result.$2 != null) _controls = result.$2;
      final current = result.$2;
      if (current != null &&
          _pending != null &&
          (!(_pendingAction == 'cancel'
                  ? current.canCancel
                  : current.canControl) ||
              (current.execution?.sequence ?? 0) > _pendingSequence!)) {
        // A late copy of this command is now fenced by revision/sequence CAS.
        _pending = null;
        _pendingSequence = null;
        _pendingAction = null;
      }
      _error = result.$3;
    });
  }

  Future<void> _refresh() async {
    _accept(await _read());
  }

  Future<void> _control(String action) async {
    if (_busy ||
        _pending != null ||
        _error != null ||
        (action == 'cancel' ? _controls?.canCancel : _controls?.canControl) !=
            true) {
      return;
    }
    final controls = _controls!;
    _pendingSequence = controls.execution?.sequence ?? 0;
    _pendingAction = action;
    _pending = jsonEncode({
      'requestId': const Uuid().v4(),
      'runId': controls.runId,
      'revision': controls.revision,
      'expectedSequence': _pendingSequence,
      'action': action,
    });
    await _submit();
  }

  Future<void> _submit() async {
    if (_busy || _pending == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.controlExecution(_pending!);
      if (!mounted) return;
      _pending = null;
      _pendingSequence = null;
      _pendingAction = null;
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
    super.build(context);
    final controls = _controls;
    if (controls == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error is WorkflowLifecycleUpdateRequired
                ? 'Update Required'
                : _error != null
                ? 'Workflow Unavailable'
                : 'Loading workflow...',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_error != null) SelectableText(_error.toString()),
          TextButton(
            onPressed: _refresh,
            child: const Text('Refresh Workflow'),
          ),
          const SizedBox(height: AleraTokens.space12),
        ],
      );
    }
    return WorkflowRunControlPanel(
      controls: controls,
      onControl: _control,
      onReview: widget.onReview,
      onCorrection: widget.onCorrection,
      onRefresh: _refresh,
      busy: _busy,
      error: _error,
      onRetry: _pending == null ? null : _submit,
    );
  }
}
