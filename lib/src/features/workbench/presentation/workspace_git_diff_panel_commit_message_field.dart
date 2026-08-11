part of 'workspace_git_diff_panel.dart';

class _CommitMessageField extends StatelessWidget {
  const _CommitMessageField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.generating,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool generating;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = TextField(
      key: const ValueKey<String>('source-control-message-field'),
      controller: controller,
      focusNode: focusNode,
      contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
      enabled: enabled && !generating,
      minLines: 3,
      maxLines: 6,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AleraTokens.surface,
        hintText: 'Message',
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundFaint,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AleraTokens.space8,
          AleraTokens.space16,
          AleraTokens.space48,
          AleraTokens.space8,
        ),
        border: _messageBorder(AleraTokens.borderSubtle),
        enabledBorder: _messageBorder(AleraTokens.borderSubtle),
        focusedBorder: _messageBorder(AleraTokens.border),
      ),
    );
    if (!generating) {
      return AiDictationFieldOverlay(
        controller: controller,
        focusNode: focusNode,
        initialPrompt:
            'The user is writing a Git commit message for staged changes.',
        controlKey: const ValueKey<String>('source-control-dictation-control'),
        enabled: enabled,
        child: field,
      );
    }
    return Stack(
      children: <Widget>[
        field,
        Positioned.fill(
          child: AbsorbPointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AleraTokens.barrierDark,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AleraTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    border: Border.all(color: AleraTokens.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space12,
                      vertical: AleraTokens.space8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space8),
                        Text(
                          'Generating with AI',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _messageBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    borderSide: BorderSide(color: color),
  );
}
