import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:flutter/material.dart';

/// Queued file comments with Send and Clear. Presentational: the caller owns
/// the queue and what sending means.
class const WorkspaceAgentCommentDraftBar({
  super.key,
  required final List<WorkspaceAgentComment> comments,
  required final VoidCallback? onSend,
  required final VoidCallback onClear,
  required final ValueChanged<String> onRemove,
  final bool sending = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = comments.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space4,
          AleraTokens.space8,
          AleraTokens.space4,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.comment,
                  size: 16,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    count == 1 ? '1 comment' : '$count comments',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('Clear')),
                const SizedBox(width: AleraTokens.space4),
                FilledButton.icon(
                  onPressed: sending ? null : onSend,
                  icon: const Icon(AleraIcons.send, size: 16),
                  label: const Text('Send'),
                ),
              ],
            ),
            for (final comment in comments)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${comment.path}: ${comment.body}',
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  AleraIconButton(
                    tooltip: 'Remove Comment',
                    onPressed: () => onRemove(comment.id),
                    icon: AleraIcons.close,
                    iconSize: 14,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
