import 'package:flutter/material.dart';

import '../../app/theme/alera_tokens.dart';

class AleraHistoryEditStatus extends StatelessWidget {
  const AleraHistoryEditStatus({
    super.key,
    required this.phase,
    this.error,
    this.onRetry,
  });
  final String phase;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (phase == 'completed') return const SizedBox.shrink();
    final message = switch (phase) {
      'interrupting' => 'Waiting for Codex to confirm the active turn stopped.',
      'rollingBack' => 'Replacing the conversation history.',
      'rolledBack' ||
      'resending' => 'Sending the corrected message. The queue remains paused.',
      'resendFailed' => 'History was replaced, but the correction was not accepted. Retry keeps the corrected history.',
      'uncertain' => 'The operation result is uncertain. Check delivery before retrying; it will not be resent automatically.',
      _ => 'The message could not be edited.',
    };
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (error != null)
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.error),
            ),
          if (onRetry != null &&
              (phase == 'rolledBack' ||
                  phase == 'resendFailed' ||
                  phase == 'uncertain'))
            TextButton(
              onPressed: onRetry,
              child: Text(
                phase == 'uncertain' ? 'Check Delivery' : 'Retry Correction',
              ),
            ),
        ],
      ),
    );
  }
}
