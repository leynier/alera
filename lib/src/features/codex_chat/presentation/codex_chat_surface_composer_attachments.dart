part of 'codex_chat_surface.dart';

class _CodexDraftItemBar extends StatelessWidget {
  const _CodexDraftItemBar({
    required this.items,
    required this.onRemove,
    required this.onOpen,
  });

  final List<CodexDraftItem> items;
  final ValueChanged<CodexDraftItem> onRemove;
  final Future<void> Function(CodexDraftItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where((item) => item.kind != CodexDraftItemKind.mention)
        .toList(growable: false);
    if (visibleItems.isEmpty) return const SizedBox.shrink();
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
          itemCount: visibleItems.length,
          separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final item = visibleItems[index];
            return _CodexDraftChip(
              item: item,
              onRemove: () => onRemove(item),
              onOpen: item.kind == CodexDraftItemKind.mention
                  ? () => onOpen(item)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _CodexDraftChip extends StatelessWidget {
  const _CodexDraftChip({
    required this.item,
    required this.onRemove,
    required this.onOpen,
  });

  final CodexDraftItem item;
  final VoidCallback onRemove;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: onOpen == null ? null : () => unawaited(onOpen!()),
          mouseCursor: onOpen == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                ),
                child: Text(
                  item.tokenText ?? item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onRemove,
          mouseCursor: SystemMouseCursors.click,
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
    required this.draftItems,
    required this.onRemoveAttachment,
    required this.onRemoveDraftItem,
    required this.onOpen,
  });

  final List<CodexInputAttachment> attachments;
  final List<CodexDraftItem> draftItems;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;
  final ValueChanged<CodexDraftItem> onRemoveDraftItem;
  final Future<void> Function(String path, {required bool isImage}) onOpen;

  @override
  Widget build(BuildContext context) {
    final mentionedFiles = draftItems
        .where((item) => item.kind == CodexDraftItemKind.mention)
        .toList(growable: false);
    if (attachments.isEmpty && mentionedFiles.isEmpty) {
      return const SizedBox.shrink();
    }
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
        key: const ValueKey<String>('codex-composer-file-bar'),
        height: AleraTokens.codexAttachmentRowHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: mentionedFiles.length + ordered.length,
          separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            if (index < mentionedFiles.length) {
              final item = mentionedFiles[index];
              return _CodexFileChip(
                key: ValueKey<String>('codex-mentioned-file-${item.id}'),
                path: item.path,
                displayName: item.name,
                isImage: false,
                isDirectory: false,
                onRemove: () => onRemoveDraftItem(item),
                onOpen: () => onOpen(item.path, isImage: false),
              );
            }
            final attachment = ordered[index - mentionedFiles.length];
            return _CodexFileChip(
              key: ValueKey<String>('codex-attached-file-${attachment.path}'),
              path: attachment.path,
              displayName:
                  attachment.displayName ?? p.basename(attachment.path),
              isImage: attachment.isImage,
              isDirectory: attachment.isDirectory,
              onRemove: () => onRemoveAttachment(attachment),
              onOpen: () =>
                  onOpen(attachment.path, isImage: attachment.isImage),
            );
          },
        ),
      ),
    );
  }
}

class _CodexFileChip extends StatelessWidget {
  const _CodexFileChip({
    super.key,
    required this.path,
    required this.displayName,
    required this.isImage,
    required this.isDirectory,
    required this.onRemove,
    required this.onOpen,
  });

  final String path;
  final String displayName;
  final bool isImage;
  final bool isDirectory;
  final VoidCallback onRemove;
  final Future<void> Function() onOpen;

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
        Flexible(
          child: InkWell(
            onTap: () => unawaited(onOpen()),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space4,
                AleraTokens.space4,
                AleraTokens.space6,
                AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                      child: Image.file(
                        File(path),
                        width: AleraTokens.codexAttachmentPreviewSize,
                        height: AleraTokens.codexAttachmentPreviewSize,
                        fit: BoxFit.cover,
                        errorBuilder: _codexImageError,
                      ),
                    )
                  else
                    AleraFileIcon(
                      pathOrName: path,
                      kind: isDirectory
                          ? AleraFileIconKind.folder
                          : AleraFileIconKind.file,
                      size: AleraTokens.iconLg,
                    ),
                  const SizedBox(width: AleraTokens.space6),
                  Flexible(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        InkWell(
          onTap: onRemove,
          mouseCursor: SystemMouseCursors.click,
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
