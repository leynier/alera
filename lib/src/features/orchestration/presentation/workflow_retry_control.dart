import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class WorkflowRetryControl extends ConsumerStatefulWidget {
  const WorkflowRetryControl({
    super.key,
    required this.runId,
    required this.taskId,
    required this.revision,
    required this.workspaceId,
    required this.onPrepared,
  });
  final String runId;
  final String taskId;
  final int revision;
  final String workspaceId;
  final VoidCallback onPrepared;
  @override
  ConsumerState<WorkflowRetryControl> createState() =>
      _WorkflowRetryControlState();
}

class _WorkflowRetryControlState extends ConsumerState<WorkflowRetryControl> {
  bool _confirm = false;
  bool _busy = false;
  bool _done = false;
  String? _error;
  Map<String, Object?>? _request;

  Future<void> _prepare() async {
    if (_busy || _done) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _request ??= Map.unmodifiable({
      'requestId': const Uuid().v4(),
      'runId': widget.runId,
      'revision': widget.revision,
      'taskId': widget.taskId,
      'retryOf': widget.workspaceId,
    });
    try {
      final result = await ref
          .read(workflowLifecycleRepositoryProvider)
          .prepareRetry(_request!);
      if (result['phase'] != 'ready') {
        throw StateError(
          'The new attempt needs inspection before it can run. Refresh the inspector for its setup status.',
        );
      }
      if (!mounted) return;
      setState(() => _done = true);
      widget.onPrepared();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_done)
        const Text(
          'The new attempt is prepared. Return to the run to resume execution.',
        )
      else if (!_confirm)
        OutlinedButton(
          onPressed: () => setState(() => _confirm = true),
          child: const Text('Prepare New Attempt'),
        )
      else ...[
        const Text(
          'Prepare a fresh worktree from the current integration commit. The previous worktree and its changes are retained. No worker is launched by this action.',
        ),
        const SizedBox(height: AleraTokens.space8),
        if (_error != null) SelectableText(_error!),
        if (_error != null)
          const Text(
            'Retry sends the same request. Refresh the inspector to inspect any worktree already created.',
          ),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _prepare,
              child: Text(
                _busy
                    ? 'Preparing Attempt'
                    : _request == null
                    ? 'Confirm New Attempt'
                    : 'Retry Preparation',
              ),
            ),
            if (_request == null)
              TextButton(
                autofocus: true,
                onPressed: _busy
                    ? null
                    : () => setState(() => _confirm = false),
                child: const Text('Keep Current Attempt'),
              ),
          ],
        ),
      ],
    ],
  );
}
