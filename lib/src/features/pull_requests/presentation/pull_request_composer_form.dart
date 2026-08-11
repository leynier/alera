part of 'pull_request_composer.dart';

extension _PullRequestComposerForm on _PullRequestComposerState {
  Widget _buildCreateForm(ThemeData theme, {required bool aiEnabled}) {
    final enabled = !widget.busy && widget.canCreate && !_generating;
    final canGenerate =
        aiEnabled && widget.canCreate && !widget.busy && !_generating;
    final titleField = TextField(
      key: const ValueKey<String>('pull-request-title-field'),
      controller: _titleController,
      focusNode: _titleFocusNode,
      contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
      enabled: enabled,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: pullRequestFieldDecoration(
        theme,
        hint: 'Title',
        hasTrailingControl: true,
      ),
      onChanged: (_) {
        if (_errorText != null) {
          _update(() => _errorText = null);
        }
      },
    );
    final descriptionField = TextField(
      key: const ValueKey<String>('pull-request-description-field'),
      controller: _bodyController,
      focusNode: _bodyFocusNode,
      contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
      enabled: enabled,
      minLines: 3,
      maxLines: 20,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: pullRequestFieldDecoration(
        theme,
        hint: 'Description',
        hasTrailingControl: true,
      ),
    );
    final titleWithDictation = AiDictationFieldOverlay(
      controller: _titleController,
      focusNode: _titleFocusNode,
      initialPrompt: 'The user is writing a pull request title.',
      controlKey: const ValueKey<String>(
        'pull-request-title-dictation-control',
      ),
      enabled: enabled,
      child: titleField,
    );
    final descriptionWithDictation = AiDictationFieldOverlay(
      controller: _bodyController,
      focusNode: _bodyFocusNode,
      initialPrompt: 'The user is writing a pull request description.',
      controlKey: const ValueKey<String>(
        'pull-request-description-dictation-control',
      ),
      enabled: enabled,
      child: descriptionField,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraDropdownField<String>(
          labelText: 'Base Branch',
          value: _baseBranch,
          enabled: enabled,
          entries: _baseEntries,
          onChanged: (value) {
            _update(() {
              _baseBranch = value;
              _errorText = null;
            });
          },
        ),
        const SizedBox(height: AleraTokens.space12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Title',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
            if (aiEnabled || _generating)
              _AiPullRequestButton(
                generating: _generating,
                canGenerate: canGenerate,
                onGenerate: () => unawaited(_generateDetails()),
                onCancel: _cancelGenerate,
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space4),
        if (_generating)
          _AiDimmedBlock(child: titleWithDictation)
        else
          titleWithDictation,
        const SizedBox(height: AleraTokens.space12),
        _labeledField(
          theme,
          label: 'Description',
          child: _generating
              ? _AiGeneratingOverlay(child: descriptionWithDictation)
              : descriptionWithDictation,
        ),
      ],
    );
  }

  Widget _labeledField(
    ThemeData theme, {
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        child,
      ],
    );
  }
}
