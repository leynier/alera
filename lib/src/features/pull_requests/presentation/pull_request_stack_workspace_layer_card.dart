part of 'pull_request_stack_workspace_dialog.dart';

class const _WorkspaceLayerCard({
  required final int index,
  required final int total,
  required final _WorkspaceLayerDraft layer,
  required final String baseBranch,
  required final bool removable,
  required final VoidCallback onMoveUp,
  required final VoidCallback onMoveDown,
  required final VoidCallback onRemove,
  required final ValueChanged<bool> onDraftChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = layer.candidate;
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${index + 1}. ${candidate.name}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  candidate.branch,
                  overflow: .ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
              AleraIconButton(
                tooltip: 'Move Up',
                icon: AleraIcons.arrowUp,
                onPressed: index == 0 ? null : onMoveUp,
              ),
              AleraIconButton(
                tooltip: 'Move Down',
                icon: AleraIcons.arrowDown,
                onPressed: index == total - 1 ? null : onMoveDown,
              ),
              AleraIconButton(
                tooltip: 'Remove Workspace',
                icon: AleraIcons.delete,
                onPressed: removable ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space6),
          Text(
            '${candidate.branch} → $baseBranch',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            controller: layer.titleController,
            labelText: 'Pull Request Title',
          ),
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            controller: layer.bodyController,
            labelText: 'Pull Request Description',
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraCheckbox(
            value: layer.draft,
            onChanged: onDraftChanged,
            label: 'Create As Draft',
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Title, description, and draft status are used only when this branch has no open pull request.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceLayerDraft({
  required final ReviewStackWorkspaceCandidate candidate,
  required String title,
  required String? body,
  required var bool draft,
}) {
  this
    : titleController = TextEditingController(text: title),
      bodyController = TextEditingController(text: body);

  final TextEditingController titleController;
  final TextEditingController bodyController;

  void dispose() {
    titleController.dispose();
    bodyController.dispose();
  }
}
