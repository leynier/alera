part of 'codex_chat_surface.dart';

class _CodexComposer extends StatelessWidget {
  const _CodexComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.interrupting,
    required this.attachments,
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
  final VoidCallback onSend;
  final VoidCallback onSteer;
  final Future<void> Function() onStop;
  final Future<void> Function() onPaste;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          AleraIconButton(
            tooltip: 'Paste',
            icon: AleraIcons.paste,
            onPressed: () => unawaited(onPaste()),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (attachments.isNotEmpty)
                  Wrap(
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
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Message Codex',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (busy) TextButton(onPressed: onSteer, child: const Text('Steer')),
          AleraIconButton(
            tooltip: busy ? 'Stop' : 'Send',
            icon: busy ? AleraIcons.stop : AleraIcons.send,
            iconColor: busy ? AleraTokens.warning : AleraTokens.foreground,
            onPressed: busy
                ? (interrupting ? null : () => unawaited(onStop()))
                : onSend,
          ),
        ],
      ),
    );
  }
}

class _CodexQueueBar extends StatelessWidget {
  const _CodexQueueBar({required this.messages, required this.onRemove});

  final List<CodexQueuedMessage> messages;
  final ValueChanged<int> onRemove;

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
