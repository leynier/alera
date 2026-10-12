import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:flutter/material.dart';

/// Loading, Update Required or unavailable, for one read of the Runs section.
/// A host without `runsV1` gets Update Required, never a guess.
class const RunReadState({
  super.key,
  final Object? error,
  required final VoidCallback onRefresh,
  final String subject = 'runs',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incompatible = error is RunsUpdateRequired;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space24),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            error == null
                ? 'Loading'
                : incompatible
                ? 'Update Required'
                : 'Runs Unavailable',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            error == null
                ? 'Waiting for the runtime.'
                : incompatible
                ? 'Update the runtime host, then reconnect. This host cannot provide $subject safely.'
                : 'The runtime could not provide $subject. Reconnect or refresh to recover.',
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            SelectableText(
              runErrorMessage(error!),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(AleraIcons.refresh, size: AleraTokens.iconMd),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Load More / page error at the end of a paged list.
class const RunPageFooter({
  super.key,
  required final bool hasMore,
  required final bool loading,
  final Object? error,
  required final VoidCallback onMore,
  required final VoidCallback onRefresh,
  final String label = 'Load More',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (error == null && !hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (error != null) ...<Widget>[
            const Text(
              'This page could not be loaded. Refresh to recover a consistent list.',
            ),
            TextButton(onPressed: onRefresh, child: const Text('Refresh')),
          ] else
            OutlinedButton(
              onPressed: loading ? null : onMore,
              child: Text(loading ? 'Loading…' : label),
            ),
        ],
      ),
    );
  }
}
