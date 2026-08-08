part of 'codex_chat_surface.dart';

class _CodexDraftItemBar extends StatelessWidget {
  const _CodexDraftItemBar({required this.items, required this.onRemove});

  final List<CodexDraftItem> items;
  final ValueChanged<CodexDraftItem> onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: AleraTokens.codexDraftChipHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final item = items[index];
            return _CodexDraftChip(item: item, onRemove: () => onRemove(item));
          },
        ),
      ),
    );
  }
}

class _CodexDraftChip extends StatelessWidget {
  const _CodexDraftChip({required this.item, required this.onRemove});

  final CodexDraftItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: AleraTokens.space8),
          child: Icon(
            switch (item.kind) {
              CodexDraftItemKind.skill => AleraIcons.agent,
              CodexDraftItemKind.app => AleraIcons.link,
              CodexDraftItemKind.mention => AleraIcons.fileGeneric,
            },
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
          child: Text(
            item.tokenText ?? item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        InkWell(
          onTap: onRemove,
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
          child: const Padding(
            padding: EdgeInsets.all(AleraTokens.space4),
            child: Icon(
              AleraIcons.close,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CodexAttachmentBar extends StatelessWidget {
  const _CodexAttachmentBar({
    required this.attachments,
    required this.onRemove,
  });

  final List<CodexInputAttachment> attachments;
  final ValueChanged<CodexInputAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final ordered = <CodexInputAttachment>[
      ...attachments.where((attachment) => attachment.isImage),
      ...attachments.where((attachment) => !attachment.isImage),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: AleraTokens.codexAttachmentRowHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ordered.length,
          separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final attachment = ordered[index];
            return _CodexAttachmentChip(
              attachment: attachment,
              onRemove: () => onRemove(attachment),
            );
          },
        ),
      ),
    );
  }
}

class _CodexAttachmentChip extends StatelessWidget {
  const _CodexAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final CodexInputAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(
      maxWidth: AleraTokens.masterDetailDefaultWidth,
    ),
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: attachment.isImage
              ? () => _showCodexImagePreview(context, attachment.path)
              : () => unawaited(launchUrl(Uri.file(attachment.path))),
          child: Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space4),
            child: attachment.isImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                    child: Image.file(
                      File(attachment.path),
                      width: AleraTokens.codexAttachmentPreviewSize,
                      height: AleraTokens.codexAttachmentPreviewSize,
                      fit: BoxFit.cover,
                      errorBuilder: _codexImageError,
                    ),
                  )
                : Icon(
                    AleraIcons.fileGeneric,
                    size: AleraTokens.iconLg,
                    color: AleraTokens.foregroundMuted,
                  ),
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
            child: Text(
              attachment.displayName ?? p.basename(attachment.path),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        InkWell(
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(AleraTokens.space6),
            child: Icon(
              AleraIcons.close,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showCodexImagePreview(BuildContext context, String source) {
  return showDialog<void>(
    context: context,
    barrierColor: AleraTokens.barrierDark,
    builder: (context) => Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(onTap: () => Navigator.of(context).pop()),
        ),
        Center(
          child: InteractiveViewer(
            maxScale: AleraTokens.imagePreviewMaxScale,
            child: _codexImageFromSource(source),
          ),
        ),
        Positioned(
          top: AleraTokens.space16,
          right: AleraTokens.space16,
          child: AleraIconButton(
            tooltip: 'Close',
            icon: AleraIcons.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    ),
  );
}

class _CodexQueueBar extends StatelessWidget {
  const _CodexQueueBar({
    required this.messages,
    required this.canSteer,
    required this.onRemove,
    required this.onEdit,
    required this.onSteer,
  });

  final List<CodexQueuedMessage> messages;
  final bool canSteer;
  final ValueChanged<int> onRemove;
  final void Function(int index, CodexQueuedMessage message) onEdit;
  final Future<void> Function(int index, CodexQueuedMessage message) onSteer;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AleraTokens.codexConversationMaxWidth,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${messages.length} Queued ${messages.length == 1 ? 'Message' : 'Messages'}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            for (final (index, message) in messages.indexed)
              InkWell(
                onTap: () => onEdit(index, message),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space4,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          message.text.isEmpty ? 'Attachment' : message.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (message.attachments.isNotEmpty)
                        Text(
                          '${message.attachments.length} Files',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      AleraIconButton(
                        tooltip: 'Steer Active Turn',
                        icon: AleraIcons.send,
                        onPressed: canSteer
                            ? () => unawaited(onSteer(index, message))
                            : null,
                      ),
                      AleraIconButton(
                        tooltip: 'Edit Queued Message',
                        icon: AleraIcons.edit,
                        onPressed: () => onEdit(index, message),
                      ),
                      AleraIconButton(
                        tooltip: 'Remove Queued Message',
                        icon: AleraIcons.close,
                        onPressed: () => onRemove(index),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CodexFailure extends StatelessWidget {
  const _CodexFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
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

class _CodexInlineError extends StatelessWidget {
  const _CodexInlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
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

class _CodexRecoveryBanner extends StatelessWidget {
  const _CodexRecoveryBanner({required this.message, required this.onContinue});

  final String message;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    key: const ValueKey<String>('codex-thread-recovery'),
    content: Text(
      '$message Earlier messages remain visible, but they are not part of the new model context.',
    ),
    leading: const Icon(AleraIcons.warning),
    actions: <Widget>[
      TextButton(
        onPressed: () => unawaited(onContinue()),
        child: const Text('Continue In New Thread'),
      ),
    ],
  );
}
