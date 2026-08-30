import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/orchestration/application/run_policy_providers.dart';
import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:alera/src/features/orchestration/presentation/run_policy_stage_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _kDialogMaxWidth = 720;
const double _kDialogMaxHeight = 640;

Future<void> showRunPolicyReviewDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RunPolicyReviewDialog(),
  );
}

/// Review surface for stage plans a coordinator proposed. While a plan sits
/// unresolved the run does not schedule, so this is the step that unblocks it.
class const RunPolicyReviewDialog({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RunPolicyReviewDialog> createState() =>
      _RunPolicyReviewDialogState();
}

class _RunPolicyReviewDialogState extends ConsumerState<RunPolicyReviewDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _busyRunId;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policiesAsync = ref.watch(runExecutionPoliciesProvider);
    return AleraDialog(
      maxWidth: _kDialogMaxWidth,
      maxHeight: _kDialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            Text(
              'Execution Plans',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AleraTokens.foreground,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: policiesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AleraEmptyState(
                  icon: AleraIcons.workspaceChildren,
                  title: 'Plans unavailable',
                  message: error.toString(),
                ),
                data: _buildPolicies,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicies(List<RunExecutionPolicy> policies) {
    if (policies.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.workspaceChildren,
        title: 'No execution plans',
        message: 'A coordinator proposes a plan before it starts dispatching.',
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          for (final policy in policies) ...<Widget>[
            AleraPanel(
              clipBehavior: .antiAlias,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: RunPolicyStageList(policy: policy),
                ),
                if (policy.status.isPending) _buildDecision(policy),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
          ],
        ],
      ),
    );
  }

  Widget _buildDecision(RunExecutionPolicy policy) {
    final busy = _busyRunId == policy.runId;
    return Padding(
      padding: const EdgeInsets.only(
        left: AleraTokens.space12,
        right: AleraTokens.space12,
        bottom: AleraTokens.space12,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraTextField(
            controller: _reasonController,
            labelText: 'Rejection Reason',
            prefixIcon: AleraIcons.text,
            enabled: !busy,
          ),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: busy ? null : () => _approve(policy),
                icon: Icon(busy ? AleraIcons.loading : AleraIcons.check),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _reject(policy),
                icon: const Icon(AleraIcons.cancel),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approve(RunExecutionPolicy policy) async {
    await _decide(
      policy,
      () => ref.read(runPolicyRepositoryProvider).approve(policy.runId),
    );
  }

  Future<void> _reject(RunExecutionPolicy policy) async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'A rejection needs a reason.');
      return;
    }
    await _decide(
      policy,
      () => ref.read(runPolicyRepositoryProvider).reject(policy.runId, reason),
    );
  }

  Future<void> _decide(
    RunExecutionPolicy policy,
    Future<RunExecutionPolicy> Function() action,
  ) async {
    setState(() {
      _busyRunId = policy.runId;
      _error = null;
    });
    try {
      await action();
      if (!mounted) {
        return;
      }
      _reasonController.clear();
      setState(() => _busyRunId = null);
      ref.invalidate(runExecutionPoliciesProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busyRunId = null;
        _error = error.toString();
      });
    }
  }
}
