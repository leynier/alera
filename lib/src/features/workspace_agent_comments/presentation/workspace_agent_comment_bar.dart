import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dispatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceAgentCommentDraftScope({
  super.key,
  required this.workspaceId,
}) extends ConsumerWidget {
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(
      workspaceAgentCommentControllerProvider(workspaceId),
    );
    if (comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        WorkspaceAgentCommentDraftBar(
          comments: comments,
          onSend: () => unawaited(
            dispatchWorkspaceAgentComments(
              context,
              ref,
              workspaceId: workspaceId,
            ),
          ),
          onClear: () => ref
              .read(
                workspaceAgentCommentControllerProvider(workspaceId).notifier,
              )
              .clear(),
          onRemove: (id) => ref
              .read(
                workspaceAgentCommentControllerProvider(workspaceId).notifier,
              )
              .remove(id),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
      ],
    );
  }
}

class const WorkspaceAgentCommentDraftBar({
  super.key,
  required this.comments,
  required this.onSend,
  required this.onClear,
  required this.onRemove,
}) extends StatelessWidget {
  final List<WorkspaceAgentComment> comments;
  final VoidCallback onSend;
  final VoidCallback onClear;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countLabel = comments.length == 1
        ? '1 Comment'
        : '${comments.length} Comments';
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space8,
          AleraTokens.space6,
          AleraTokens.space8,
          AleraTokens.space8,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.comment,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    countLabel,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onSend,
                  child: const Text(
                    'Send to Agent',
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Clear Comments',
                  icon: AleraIcons.delete,
                  onPressed: onClear,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: comments.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AleraTokens.space4),
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  return _DraftCommentRow(
                    comment: comment,
                    onRemove: () => onRemove(comment.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _DraftCommentRow({required this.comment, required this.onRemove})
    extends StatelessWidget {
  final WorkspaceAgentComment comment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: .start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Text(
                workspaceAgentCommentLocationLabel(comment),
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(height: AleraTokens.space2),
              Text(
                comment.body,
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ],
          ),
        ),
        AleraIconButton(
          tooltip: 'Remove Comment',
          icon: AleraIcons.close,
          onPressed: onRemove,
        ),
      ],
    );
  }
}
