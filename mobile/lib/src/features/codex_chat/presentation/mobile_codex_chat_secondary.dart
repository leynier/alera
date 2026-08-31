part of 'mobile_codex_chat_screen.dart';

class _MobileQueueBar extends StatelessWidget {
  const _MobileQueueBar({required this.messages, required this.controller});
  final List<Map<String, Object?>> messages;
  final MobileCodexController controller;
  @override
  Widget build(BuildContext context) {
    final owner = context
        .findAncestorStateOfType<_MobileCodexChatScreenState>();
    final state = owner?.ref
        .read(
          mobileCodexControllerProvider(
            owner.widget.hostId,
            owner.widget.tabId,
          ),
        )
        .value;
    return AleraMessageQueue(
      messages: [
        for (final message in messages)
          AleraQueuedMessageRow(
            id: message['id'].toString(),
            text: message['text']?.toString() ?? '',
            attachmentCount: (message['attachments'] as List?)?.length ?? 0,
            hasImage: (message['attachments'] as List? ?? const [])
                .whereType<Map>()
                .any((a) => a['type'] == 'localImage'),
            status: message['status']?.toString() ?? 'queued',
            error: message['error']?.toString(),
          ),
      ],
      paused: state?.queuePaused ?? false,
      canSteer:
          state?.activeTurnId != null &&
          state?.interrupting != true &&
          state?.historyLocked != true,
      onTogglePaused: () => unawaited(
        controller.queueAction(state!.queuePaused ? 'resume' : 'pause'),
      ),
      onReconcile: () => unawaited(controller.queueAction('reconcile')),
      onRemove: (id) async {
        await controller.removeQueuedMessageById(
          id,
          revision: state?.queueState['revision'] as int?,
        );
      },
      onSteer: (id) async {
        final message = messages
            .where((entry) => entry['id'] == id)
            .firstOrNull;
        if (message != null) {
          await controller.steerQueuedMessage(
            message,
            revision: state?.queueState['revision'] as int?,
          );
        }
      },
      onEdit: (id) async {
        final message = messages
            .where((entry) => entry['id'] == id)
            .firstOrNull;
        if (message == null) return;
        final revision = state?.queueState['revision'] as int?;
        await showDialog<void>(
          context: context,
          builder: (_) => AleraMessageEditor(
            text: message['text']?.toString() ?? '',
            attachmentCount: (message['attachments'] as List?)?.length ?? 0,
            onSave: (text) async =>
                await controller.saveQueuedMessage(
                  message,
                  text,
                  revision: revision,
                )
                ? null
                : 'The queue changed or the message could not be saved. Your edit has been preserved.',
          ),
        );
      },
    );
  }
}

class _MobileError extends StatelessWidget {
  const _MobileError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AleraTokens.space12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _MobileSendButton extends StatelessWidget {
  const _MobileSendButton({
    required this.busy,
    required this.disabled,
    required this.hasText,
    required this.canSteer,
    required this.onSend,
    required this.onSteer,
    required this.onStop,
  });

  final bool busy;
  final bool disabled;
  final bool hasText;
  final bool canSteer;
  final Future<void> Function() onSend;
  final Future<void> Function() onSteer;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final steering = busy && canSteer;
    return IconButton.filled(
      tooltip: busy ? (steering ? 'Steer' : 'Stop') : 'Send',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AleraTokens.space32),
        backgroundColor: busy || hasText
            ? AleraTokens.foreground
            : AleraTokens.foregroundMuted,
        foregroundColor: AleraTokens.background,
      ),
      onPressed: disabled || (!busy && !hasText)
          ? null
          : () =>
                unawaited(busy ? (steering ? onSteer() : onStop()) : onSend()),
      icon: Icon(
        busy && !steering ? Icons.stop_rounded : Icons.arrow_upward,
        size: AleraTokens.space16,
      ),
    );
  }
}

class _MobileRequestCard extends StatelessWidget {
  const _MobileRequestCard({
    required this.title,
    this.body,
    this.bodyWidget,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? bodyWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
    padding: const EdgeInsets.all(AleraTokens.space12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (body != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(body!),
        ],
        if (bodyWidget != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          bodyWidget!,
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Wrap(spacing: AleraTokens.space8, children: actions),
        ],
      ],
    ),
  );
}
