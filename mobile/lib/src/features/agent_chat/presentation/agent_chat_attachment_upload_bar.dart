import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Where the composer's attachment upload stands. The phone uploads a file
/// as soon as it is picked, so Send waits until the runtime has it.
sealed class const AgentChatAttachmentUploadStatus();

/// [uploadedBytes] of [totalBytes] of the file in flight. A total of zero
/// means the upload does not report progress.
final class const AgentChatAttachmentUploading({
  final int uploadedBytes = 0,
  final int totalBytes = 0,
}) extends AgentChatAttachmentUploadStatus {
  double? get fraction => totalBytes <= 0
      ? null
      : (uploadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
}

/// A picked file never reached the runtime. The picker kept no copy of it,
/// so Retry picks again.
final class const AgentChatAttachmentUploadFailed()
    extends AgentChatAttachmentUploadStatus;

/// Shown above the composer while an attachment uploads, or after one
/// failed.
class const AgentChatAttachmentUploadBar({
  super.key,
  required final AgentChatAttachmentUploadStatus status,
  required final VoidCallback? onRetry,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Container(
      key: const Key('agent-chat-attachment-upload'),
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: switch (status) {
        AgentChatAttachmentUploading(:final fraction) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('Uploading attachment', style: muted)),
                  if (fraction != null)
                    Text('${(fraction * 100).floor()}%', style: muted),
                ],
              ),
              const SizedBox(height: AleraTokens.space6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusXs),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: AleraTokens.progressBarHeight,
                ),
              ),
            ],
          ),
        ),
        AgentChatAttachmentUploadFailed() => Row(
          children: <Widget>[
            const Icon(
              AleraIcons.warning,
              size: AleraTokens.iconSm,
              color: AleraTokens.error,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                'The attachment did not upload.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: .compact,
              onPressed: onDismiss,
              icon: const Icon(AleraIcons.close, size: AleraTokens.iconSm),
            ),
          ],
        ),
      },
    );
  }
}
