part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogShell on _PromptWorkspaceDialogState {
  Widget _buildShell(ThemeData theme) {
    return AleraDialog(
      maxWidth: 620,
      maxHeight: 720,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.gitFork, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'New Workspace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: .bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _working
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(AleraIcons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraSegmentedButton<NewWorkspaceMode>(
              dense: true,
              segments: const <ButtonSegment<NewWorkspaceMode>>[
                ButtonSegment<NewWorkspaceMode>(
                  value: .fromPrompt,
                  label: Text('From Prompt'),
                  icon: Icon(AleraIcons.agent, size: 16),
                ),
                ButtonSegment<NewWorkspaceMode>(
                  value: .manual,
                  label: Text('Manual'),
                  icon: Icon(AleraIcons.gitBranch, size: 16),
                ),
              ],
              selected: _mode,
              onSelectionChanged: _working ? (_) {} : _selectMode,
            ),
            const SizedBox(height: AleraTokens.space20),
            if (_mode == NewWorkspaceMode.manual)
              _buildManualMode(theme)
            else
              _buildPromptMode(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildManualMode(ThemeData theme) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          'Choose every workspace setting yourself, including the branch name and optional parent workspace.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop(const PromptWorkspaceDialogResult(openManual: true)),
            child: const Text('Continue Manually'),
          ),
        ),
      ],
    );
  }
}
