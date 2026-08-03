part of 'codex_chat_surface.dart';

class _CodexComposer extends StatelessWidget {
  const _CodexComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.interrupting,
    required this.attachments,
    required this.state,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onPermissionChanged,
    required this.onPlanChanged,
    required this.onCollaborationChanged,
    required this.onInsertToken,
    required this.onCompact,
    required this.onReview,
    required this.onSend,
    required this.onSteer,
    required this.onStop,
    required this.onPaste,
    required this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool interrupting;
  final List<CodexInputAttachment> attachments;
  final CodexChatState state;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String> onPermissionChanged;
  final ValueChanged<bool> onPlanChanged;
  final ValueChanged<String?> onCollaborationChanged;
  final ValueChanged<String> onInsertToken;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onSend;
  final VoidCallback onSteer;
  final Future<void> Function() onStop;
  final Future<void> Function() onPaste;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _CodexComposerOptions(
        state: state,
        onModelChanged: onModelChanged,
        onReasoningChanged: onReasoningChanged,
        onSpeedChanged: onSpeedChanged,
        onPermissionChanged: onPermissionChanged,
        onPlanChanged: onPlanChanged,
        onCollaborationChanged: onCollaborationChanged,
        onInsertToken: onInsertToken,
        onCompact: onCompact,
        onReview: onReview,
      ),
      const SizedBox(height: AleraTokens.space8),
      AleraComposer(
        controller: controller,
        focusNode: focusNode,
        enabled: !interrupting,
        hasAttachments: attachments.isNotEmpty,
        attachmentBar: attachments.isEmpty
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AleraTokens.space8,
                    AleraTokens.space8,
                    AleraTokens.space8,
                    0,
                  ),
                  child: Wrap(
                    spacing: AleraTokens.space4,
                    runSpacing: AleraTokens.space4,
                    children: <Widget>[
                      for (final attachment in attachments)
                        InputChip(
                          label: Text(
                            p.basename(attachment.path),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => onRemoveAttachment(attachment),
                        ),
                    ],
                  ),
                ),
              ),
        onPaste: () async {
          await onPaste();
          return true;
        },
        onSend: busy ? onSteer : onSend,
        onClose: busy ? () => unawaited(onStop()) : () {},
        textActions: const <AleraTextActionMenuItem>[],
        onTextActionSelected: (_) {},
        hintText: 'Message Codex',
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space8,
            0,
            AleraTokens.space8,
            AleraTokens.space8,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AleraIconButton(
                    tooltip: 'Paste',
                    icon: AleraIcons.paste,
                    onPressed: interrupting ? null : () => unawaited(onPaste()),
                  ),
                ),
              ),
              if (busy)
                TextButton(onPressed: onSteer, child: const Text('Steer')),
              AleraIconButton(
                tooltip: busy ? 'Stop' : 'Send',
                icon: busy ? AleraIcons.stop : AleraIcons.send,
                iconColor: busy ? AleraTokens.warning : AleraTokens.foreground,
                onPressed: interrupting
                    ? null
                    : busy
                    ? () => unawaited(onStop())
                    : onSend,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _CodexComposerOptions extends StatelessWidget {
  const _CodexComposerOptions({
    required this.state,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onPermissionChanged,
    required this.onPlanChanged,
    required this.onCollaborationChanged,
    required this.onInsertToken,
    required this.onCompact,
    required this.onReview,
  });

  final CodexChatState state;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String> onPermissionChanged;
  final ValueChanged<bool> onPlanChanged;
  final ValueChanged<String?> onCollaborationChanged;
  final ValueChanged<String> onInsertToken;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;

  @override
  Widget build(BuildContext context) {
    final model = state.selectedModel ?? state.models.firstOrNull?.id;
    final reasoning =
        state.selectedModelOption?.reasoningEfforts
            .where((value) => value.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final reasoningValues = reasoning.isEmpty
        ? const <String>['low', 'medium', 'high', 'xhigh']
        : reasoning;
    final speedValues = state.selectedModelOption?.supportsFastMode == true
        ? const <String>['normal', 'fast']
        : const <String>['normal'];
    return Wrap(
      spacing: AleraTokens.space4,
      runSpacing: AleraTokens.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        DropdownButton<String>(
          value: state.models.any((item) => item.id == model) ? model : null,
          hint: const Text('Model'),
          dropdownColor: AleraTokens.surfaceElevated,
          underline: const SizedBox.shrink(),
          items: <DropdownMenuItem<String>>[
            for (final option in state.models)
              DropdownMenuItem<String>(
                value: option.id,
                child: Text(option.label),
              ),
          ],
          onChanged: onModelChanged,
        ),
        if (state.snapshot.contextUsed != null)
          Text(
            'Context: ${state.snapshot.contextUsed}/${state.snapshot.contextLimit ?? '?'}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        _CodexCatalogButton(
          label: 'Skills',
          prefix: '/skill ',
          items: state.skills,
          onSelected: onInsertToken,
        ),
        _CodexCatalogButton(
          label: 'Apps',
          prefix: '/app ',
          items: state.apps,
          onSelected: onInsertToken,
        ),
        _CodexMentionButton(onSelected: onInsertToken),
        _CodexChoiceButton(
          label: 'Reasoning: ${_choiceLabel(state.reasoningEffort)}',
          values: reasoningValues,
          value: state.reasoningEffort,
          onChanged: onReasoningChanged,
        ),
        _CodexChoiceButton(
          label: 'Speed: ${_choiceLabel(state.speedMode)}',
          values: speedValues,
          value: state.speedMode,
          onChanged: onSpeedChanged,
        ),
        _CodexChoiceButton(
          label: 'Permission: ${_choiceLabel(state.permissionMode)}',
          values: const <String>['on-request', 'never'],
          value: state.permissionMode,
          onChanged: onPermissionChanged,
        ),
        FilterChip(
          label: const Text('Plan'),
          selected: state.planMode,
          onSelected: onPlanChanged,
        ),
        _CodexCollaborationButton(
          modes: state.collaborationModes,
          value: state.collaborationMode,
          onChanged: onCollaborationChanged,
        ),
        AleraIconButton(
          tooltip: 'Compact Context',
          icon: AleraIcons.collapseAll,
          onPressed: () => unawaited(onCompact()),
        ),
        AleraIconButton(
          tooltip: 'Start Review',
          icon: AleraIcons.checks,
          onPressed: () => unawaited(onReview()),
        ),
      ],
    );
  }
}

class _CodexQueueBar extends StatelessWidget {
  const _CodexQueueBar({
    required this.messages,
    required this.onRemove,
    required this.onEdit,
  });

  final List<CodexQueuedMessage> messages;
  final ValueChanged<int> onRemove;
  final void Function(int index, CodexQueuedMessage message) onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AleraTokens.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      child: Wrap(
        spacing: AleraTokens.space8,
        children: <Widget>[
          const Text('Queued Messages'),
          for (final (index, message) in messages.indexed)
            InputChip(
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  message.text.isEmpty ? 'Attachment' : message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onPressed: () => onEdit(index, message),
              onDeleted: () => onRemove(index),
            ),
        ],
      ),
    );
  }
}

class _CodexFailure extends StatelessWidget {
  const _CodexFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.emptyStateMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AleraTokens.space12),
            FilledButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(AleraIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodexInlineError extends StatelessWidget {
  const _CodexInlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      leading: const Icon(AleraIcons.warning),
      actions: <Widget>[
        TextButton(
          onPressed: () => unawaited(onRetry()),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
