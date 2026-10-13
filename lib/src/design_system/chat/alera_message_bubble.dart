import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:flutter/material.dart';

/// One message of a conversation. Outgoing messages (what the user sent) sit
/// on the trailing edge, incoming ones on the leading edge. The heading names
/// the kind and the sender, an optional badge carries a status, [isNew] marks
/// an unread incoming message and [timestamp] is preformatted by the caller.
class const AleraMessageBubble({
  super.key,
  required final String heading,
  required final String body,
  required final bool outgoing,
  final String? timestamp,
  final String? statusLabel,
  final AleraBadgeTone statusTone = AleraBadgeTone.neutral,
  final bool isNew = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AleraTokens.space8),
        padding: const EdgeInsets.all(AleraTokens.space12),
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.chatBubbleMaxWidth,
        ),
        decoration: BoxDecoration(
          color: outgoing ? AleraTokens.surface : AleraTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.border),
        ),
        child: Column(
          crossAxisAlignment: .start,
          spacing: AleraTokens.space6,
          children: <Widget>[
            Row(
              spacing: AleraTokens.space6,
              children: <Widget>[
                Flexible(
                  child: Text(
                    heading,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (statusLabel != null)
                  AleraBadge(label: statusLabel!, tone: statusTone),
                if (isNew)
                  const AleraBadge(label: 'New', tone: AleraBadgeTone.accent),
                const Spacer(),
                if (timestamp != null && timestamp!.isNotEmpty)
                  Text(timestamp!, style: muted),
              ],
            ),
            SelectableText(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
