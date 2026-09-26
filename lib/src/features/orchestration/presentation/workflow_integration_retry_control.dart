import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowIntegrationRetryControl extends ConsumerStatefulWidget {
  const WorkflowIntegrationRetryControl({
    super.key,
    required this.integrationId,
    required this.requestId,
    required this.runId,
    required this.revision,
    required this.taskId,
    required this.workspaceId,
    required this.onSettled,
  });

  final String integrationId;
  final String requestId;
  final String runId;
  final int revision;
  final String taskId;
  final String workspaceId;
  final VoidCallback onSettled;

  @override
  ConsumerState<WorkflowIntegrationRetryControl> createState() =>
      _WorkflowIntegrationRetryControlState();
}

class _WorkflowIntegrationRetryControlState
    extends ConsumerState<WorkflowIntegrationRetryControl> {
  bool _confirm = false;
  bool _busy = false;
  bool _attempted = false;
  bool _integrated = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy || _integrated) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(workflowLifecycleRepositoryProvider)
          .retryIntegration(
            integrationId: widget.integrationId,
            requestId: widget.requestId,
            runId: widget.runId,
            revision: widget.revision,
            taskId: widget.taskId,
            workspaceId: widget.workspaceId,
          );
      if (!mounted) return;
      setState(() {
        _integrated = result['state'] == 'integrated';
        if (!_integrated) {
          _error = result['error'] as String? ?? 'Integration still needs attention. Inspect its retained error and workspace.';
        }
      });
      widget.onSettled();
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
      if (_integrated)
        const Text(
          'The result is integrated. Return to the run and select Start Workflow to continue.',
        )
      else if (!_confirm)
        OutlinedButton(
          onPressed: () => setState(() => _confirm = true),
          child: const Text('Retry Integration'),
        )
      else ...[
        const Text(
          'Inspect the error and integration workspace first. This retries the same committed result and may update the integration commit. It does not launch a worker or resume the workflow.',
        ),
        const SizedBox(height: AleraTokens.space8),
        if (_error != null) SelectableText(_error!),
        if (_error != null)
          const Text(
            'If the response was lost, retry uses the same integration identity. Refresh the inspector to check its durable state.',
          ),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _retry,
              child: Text(
                _busy
                    ? 'Integrating Result'
                    : _attempted
                    ? 'Retry Same Integration'
                    : 'Confirm Retry Integration',
              ),
            ),
            if (!_attempted)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _confirm = false),
                child: const Text('Keep Attention'),
              ),
          ],
        ),
      ],
    ],
  );
}
