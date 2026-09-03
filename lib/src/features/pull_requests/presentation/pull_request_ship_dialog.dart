import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:flutter/material.dart';

/// Confirmation modal for Ship. Offers staged-only and stage-all flows in
/// the requested order, then cancel. Pops the selected
/// [PullRequestShipScope], or null when cancelled.
class PullRequestShipDialog extends StatelessWidget {
  const PullRequestShipDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text('Ship Changes?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Text(
              'Ship only staged changes, or stage all changes first and include them in the commit.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            FilledButton(
              key: const Key('ship-staged-changes-button'),
              onPressed: () =>
                  Navigator.of(context).pop(PullRequestShipScope.staged),
              child: const Text('Ship Staged Changes'),
            ),
            const SizedBox(height: AleraTokens.space8),
            OutlinedButton(
              key: const Key('ship-all-changes-button'),
              onPressed: () =>
                  Navigator.of(context).pop(PullRequestShipScope.all),
              child: const Text('Ship All Changes'),
            ),
            const SizedBox(height: AleraTokens.space8),
            TextButton(
              key: const Key('ship-cancel-button'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
