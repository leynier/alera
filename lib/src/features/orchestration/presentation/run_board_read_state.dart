import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:flutter/material.dart';

class RunBoardReadState extends StatelessWidget {
  const RunBoardReadState({super.key, this.error, required this.onRefresh});
  final Object? error;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final incompatible = error is RunBoardUpdateRequired;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error == null
                ? 'Loading Run Board'
                : incompatible
                ? 'Update Required'
                : 'Run Board Unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            error == null
                ? 'Waiting for the runtime snapshot.'
                : incompatible
                ? 'Update the runtime host, then reconnect. This host cannot provide the Run Board safely.'
                : 'The runtime could not provide this snapshot. Reconnect or refresh to recover.',
          ),
          if (error != null) ...[
            const SizedBox(height: AleraTokens.space12),
            SelectableText(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(AleraIcons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}

class RunBoardPageFooter extends StatelessWidget {
  const RunBoardPageFooter({
    super.key,
    required this.hasMore,
    required this.loading,
    this.error,
    required this.onMore,
    required this.onRefresh,
    this.label = 'Load More',
  });
  final bool hasMore;
  final bool loading;
  final Object? error;
  final VoidCallback onMore;
  final VoidCallback onRefresh;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          const Text(
            'This page could not be loaded. Refresh to recover a consistent snapshot.',
          ),
          TextButton(onPressed: onRefresh, child: const Text('Refresh')),
        ] else if (hasMore)
          OutlinedButton(
            onPressed: loading ? null : onMore,
            child: Text(loading ? 'Loading' : label),
          ),
      ],
    ),
  );
}

String runBoardStatusLabel(String status) => switch (status) {
  'result_ready' || 'resultReady' => 'Result Ready',
  'integrated' => 'Integrated',
  'conflict' => 'Conflict',
  'completed' => 'Completed',
  'running' => 'Running',
  'dispatched' => 'Dispatched',
  'stopped' => 'Stopped',
  'active' => 'Active',
  'closed' => 'Closed',
  'ready' => 'Ready',
  'queued' => 'Queued',
  'none' => 'Not Configured',
  'pending' => 'Pending',
  'blocked' => 'Blocked',
  'failed' => 'Failed',
  'stalled' => 'Stalled',
  'attention' => 'Attention',
  'cancelled' => 'Cancelled',
  'canceled' => 'Cancelled',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  'draft' => 'Draft',
  _ => status,
};

Color runBoardStatusColor(String status) => switch (status) {
  'failed' || 'conflict' => AleraTokens.error,
  'blocked' ||
  'stalled' ||
  'pending' ||
  'rejected' ||
  'attention' => AleraTokens.warning,
  'completed' || 'integrated' => AleraTokens.success,
  _ => AleraTokens.foregroundMuted,
};
