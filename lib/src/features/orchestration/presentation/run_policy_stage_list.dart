import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:flutter/material.dart';

/// Read-only rendering of a plan: its stages, the preferred profile per stage,
/// and the fallbacks the run may use.
class RunPolicyStageList extends StatelessWidget {
  const RunPolicyStageList({super.key, required this.policy});

  final RunExecutionPolicy policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                policy.runId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              _statusLabel(policy.status),
              style: theme.textTheme.labelSmall?.copyWith(
                color: policy.blocksDispatch
                    ? AleraTokens.warning
                    : AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
        if (policy.blocksDispatch) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Scheduling Is Held Until This Plan Is Resolved.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
        const SizedBox(height: AleraTokens.space8),
        for (final stage in policy.stages)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space4),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: stage.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                  TextSpan(
                    text: '  ${stage.profile}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  if (stage.fallbacks.isNotEmpty)
                    TextSpan(
                      text: '  fallback: ${stage.fallbacks.join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AleraTokens.space4),
        Text(
          'On Stall: ${policy.stallPolicy}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );
  }
}

String _statusLabel(RunPolicyStatus status) {
  return switch (status) {
    RunPolicyStatus.none => 'No Plan',
    RunPolicyStatus.draft => 'Awaiting Approval',
    RunPolicyStatus.approved => 'Approved',
    RunPolicyStatus.rejected => 'Rejected',
  };
}
