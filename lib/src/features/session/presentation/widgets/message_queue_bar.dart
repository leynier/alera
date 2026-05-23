import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:flutter/material.dart';

class MessageQueueBar extends StatelessWidget {
  const MessageQueueBar({
    super.key,
    required this.messages,
    required this.onRemove,
    required this.onEdit,
    required this.onSteer,
    required this.canSteer,
  });

  final List<PendingMessage> messages;
  final ValueChanged<String> onRemove;
  final ValueChanged<PendingMessage> onEdit;
  final ValueChanged<String> onSteer;
  final bool canSteer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        0,
        AleraTokens.space12,
        AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.schedule_outlined,
                  size: 13,
                  color: AleraTokens.foregroundFaint,
                ),
                const SizedBox(width: AleraTokens.space4),
                Text(
                  '${messages.length} queued',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AleraTokens.border),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: messages.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AleraTokens.border),
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _QueueItem(
                message: msg,
                onRemove: onRemove,
                onEdit: onEdit,
                onSteer: onSteer,
                canSteer: canSteer,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.message,
    required this.onRemove,
    required this.onEdit,
    required this.onSteer,
    required this.canSteer,
  });

  final PendingMessage message;
  final ValueChanged<String> onRemove;
  final ValueChanged<PendingMessage> onEdit;
  final ValueChanged<String> onSteer;
  final bool canSteer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          if (message.attachments.isNotEmpty) ...<Widget>[
            const SizedBox(width: AleraTokens.space6),
            Text(
              '+${message.attachments.length}',
              style: const TextStyle(
                fontSize: 11,
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ],
          if (canSteer) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            InkWell(
              onTap: () => onSteer(message.id),
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              mouseCursor: SystemMouseCursors.click,
              child: const Padding(
                padding: EdgeInsets.all(AleraTokens.space2),
                child: Icon(
                  Icons.arrow_upward,
                  size: 13,
                  color: AleraTokens.accent,
                ),
              ),
            ),
          ],
          const SizedBox(width: AleraTokens.space4),
          InkWell(
            onTap: () => onEdit(message),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            mouseCursor: SystemMouseCursors.click,
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space2),
              child: Icon(Icons.edit, size: 13, color: AleraTokens.accent),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          InkWell(
            onTap: () => onRemove(message.id),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            mouseCursor: SystemMouseCursors.click,
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space2),
              child: Icon(Icons.close, size: 13, color: AleraTokens.error),
            ),
          ),
        ],
      ),
    );
  }
}
