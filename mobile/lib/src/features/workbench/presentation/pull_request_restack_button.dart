import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Outlined Restack control shared by the empty composer and the linked review.
class const PullRequestRestackButton({
  super.key,
  required final bool enabled,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Rewrite committed and uncommitted changes since the merge base',
      child: OutlinedButton.icon(
        key: const Key('pull-request-restack-button'),
        onPressed: enabled ? onPressed : null,
        icon: const Icon(AleraIcons.restore),
        label: const Text('Restack Changes'),
      ),
    );
  }
}
