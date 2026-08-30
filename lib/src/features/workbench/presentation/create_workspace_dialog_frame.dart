part of 'create_workspace_dialog.dart';

class const _EmptyProjectsDialog({
  required final VoidCallback? onAddProject,
  required final VoidCallback onCancel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space24),
        child: Column(
          mainAxisSize: .min,
          children: [
            AleraEmptyState(
              icon: AleraIcons.folderOff,
              title: 'No Git projects yet',
              message: 'Linked workspaces require a Git project. Add one to get started.',
              action: onAddProject != null
                  ? FilledButton.icon(
                      onPressed: onAddProject,
                      icon: const Icon(AleraIcons.add, size: 16),
                      label: const Text('Add Git Project'),
                    )
                  : null,
            ),
            const SizedBox(height: AleraTokens.space8),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class const _CreateWorkspaceDialogFrame({
  required final bool isSelectionStep,
  required final bool creating,
  required final String? creationError,
  required final Widget step,
  required final bool createAnother,
  required final ValueChanged<bool> onCreateAnotherChanged,
  required final VoidCallback onCancel,
  required final VoidCallback onBack,
  required final VoidCallback? onContinue,
  required final VoidCallback? onCreate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: isSelectionStep ? 680 : 560,
      maxHeight: 740,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            _CreateWorkspaceDialogHeader(
              isSelectionStep: isSelectionStep,
              creating: creating,
              onBack: onBack,
            ),
            const SizedBox(height: AleraTokens.space16),
            if (creationError case final error?) ...[
              _CreateWorkspaceError(message: error),
              const SizedBox(height: AleraTokens.space12),
            ],
            Flexible(
              child: AnimatedSwitcher(
                duration: AleraTokens.durationMid,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0.0),
                        end: .zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(isSelectionStep ? 'step1' : 'step2'),
                  child: SingleChildScrollView(child: step),
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            if (!isSelectionStep) ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: AleraCheckbox(
                  value: createAnother,
                  enabled: !creating,
                  onChanged: onCreateAnotherChanged,
                  label: 'Create Another',
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
            ],
            _CreateWorkspaceDialogActions(
              isSelectionStep: isSelectionStep,
              creating: creating,
              onCancel: onCancel,
              onBack: onBack,
              onContinue: onContinue,
              onCreate: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}

class const _CreateWorkspaceDialogHeader({
  required final bool isSelectionStep,
  required final bool creating,
  required final VoidCallback onBack,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (!isSelectionStep && !creating) ...[
          IconButton(
            icon: const Icon(AleraIcons.back, size: 20),
            color: AleraTokens.foregroundMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onBack,
          ),
          const SizedBox(width: AleraTokens.space12),
        ],
        const Icon(AleraIcons.gitFork, color: AleraTokens.accent),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: Text(
            isSelectionStep
                ? 'New Workspace - Selection'
                : 'New Workspace - Settings',
            overflow: .ellipsis,
            maxLines: 1,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: .bold),
          ),
        ),
        const SizedBox(width: AleraTokens.space12),
        if (creating)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Text(
            isSelectionStep ? 'Step 1 of 2' : 'Step 2 of 2',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
      ],
    );
  }
}

class const _CreateWorkspaceError({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: .infinity,
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          const Icon(AleraIcons.error, color: AleraTokens.error, size: 16),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _CreateWorkspaceDialogActions({
  required final bool isSelectionStep,
  required final bool creating,
  required final VoidCallback onCancel,
  required final VoidCallback onBack,
  required final VoidCallback? onContinue,
  required final VoidCallback? onCreate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        TextButton(
          onPressed: isSelectionStep ? onCancel : (creating ? null : onBack),
          child: Text(isSelectionStep ? 'Cancel' : 'Back'),
        ),
        const SizedBox(width: AleraTokens.space8),
        FilledButton(
          onPressed: isSelectionStep ? onContinue : onCreate,
          child: Text(
            isSelectionStep
                ? 'Continue'
                : (creating ? 'Creating…' : 'Create Workspace'),
          ),
        ),
      ],
    );
  }
}
