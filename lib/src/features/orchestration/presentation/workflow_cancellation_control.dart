import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:flutter/material.dart';

class WorkflowCancellationControl extends StatefulWidget {
  const WorkflowCancellationControl({
    super.key,
    required this.controls,
    required this.enabled,
    required this.onCancel,
  });
  final WorkflowRunControls controls;
  final bool enabled;
  final VoidCallback onCancel;

  @override
  State<WorkflowCancellationControl> createState() =>
      _WorkflowCancellationControlState();
}

class _WorkflowCancellationControlState
    extends State<WorkflowCancellationControl> {
  bool _confirming = false;
  final _cancelFocus = FocusNode(debugLabel: 'workflow-cancel');
  final _keepFocus = FocusNode(debugLabel: 'workflow-cancel-keep');

  void _showConfirmation(bool value) {
    setState(() => _confirming = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (value ? _keepFocus : _cancelFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelFocus.dispose();
    _keepFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkflowCancellationControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controls.status != widget.controls.status) {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = widget.controls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controls.cancellationError case final String error) ...[
          Text(
            'Cancellation Needs Attention',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: AleraTokens.warning),
          ),
          SelectableText(error),
        ],
        if (controls.canCancel)
          if (_confirming) ...[
            Text(
              controls.status == 'cancelled'
                  ? 'Retry checks the remaining terminal identities and stops only those belonging to this run. It does not resume the workflow or remove its worktrees.'
                  : 'Cancellation stops this run’s coordinator and worker terminals and prevents new tasks. Worktrees, branches and results are retained. Setup or Git operations already in progress finish safely. This run cannot be resumed.',
            ),
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: [
                OutlinedButton(
                  onPressed: widget.enabled ? widget.onCancel : null,
                  child: const Text('Confirm Cancellation'),
                ),
                TextButton(
                  focusNode: _keepFocus,
                  onPressed: widget.enabled
                      ? () => _showConfirmation(false)
                      : null,
                  child: Text(
                    controls.status == 'cancelled'
                        ? 'Not Now'
                        : 'Keep Workflow',
                  ),
                ),
              ],
            ),
          ] else
            TextButton(
              focusNode: _cancelFocus,
              onPressed: widget.enabled ? () => _showConfirmation(true) : null,
              child: Text(
                controls.status == 'cancelled'
                    ? 'Retry Cancellation'
                    : 'Cancel Workflow',
              ),
            ),
      ],
    );
  }
}
