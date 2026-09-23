import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Outlined Restack control shared by the create form and the linked review.
class const PullRequestRestackButton({
  super.key,
  required final bool enabled,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Rewrite committed and uncommitted changes since the merge base',
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('pull-request-restack-button'),
          onPressed: enabled ? onPressed : null,
          icon: const Icon(AleraIcons.restore, size: 16),
          label: const Text('Restack Changes'),
        ),
      ),
    );
  }
}
