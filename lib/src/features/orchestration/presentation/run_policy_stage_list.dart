import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:flutter/material.dart';

/// Read-only rendering of a plan: its stages, the preferred profile per stage,
/// and the fallbacks the run may use.
class const RunPolicyStageList({
  super.key,
  required final RunExecutionPolicy policy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                policy.runId,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w600,
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
            'Scheduling is held until this plan is resolved.',
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
          'On stall: ${policy.stallPolicy}',
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
    RunPolicyStatus.none => 'No plan',
    RunPolicyStatus.draft => 'Awaiting approval',
    RunPolicyStatus.approved => 'Approved',
    RunPolicyStatus.rejected => 'Rejected',
  };
}
