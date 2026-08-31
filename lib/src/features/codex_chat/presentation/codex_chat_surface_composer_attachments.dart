part of 'codex_chat_surface.dart';

class const _CodexDraftItemBar({
  required final List<CodexDraftItem> items,
  required final ValueChanged<CodexDraftItem> onRemove,
  required final Future<void> Function(CodexDraftItem item) onOpen,
}) extends StatelessWidget {
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
          scrollDirection: .horizontal,
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

class const _CodexDraftChip({
  required final CodexDraftItem item,
  required final VoidCallback onRemove,
  required final Future<void> Function()? onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
    ),
    child: Row(
      mainAxisSize: .min,
      children: <Widget>[
        InkWell(
          onTap: onOpen == null ? null : () => unawaited(onOpen!()),
          mouseCursor: onOpen == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusXl),
          child: Row(
            mainAxisSize: .min,
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
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onRemove,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusXl),
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

class const _CodexAttachmentBar({
  required final List<CodexInputAttachment> attachments,
  required final List<CodexDraftItem> draftItems,
  required final ValueChanged<CodexInputAttachment> onRemoveAttachment,
  required final ValueChanged<CodexDraftItem> onRemoveDraftItem,
  required final Future<void> Function(String path, {required bool isImage})
  onOpen,
}) extends StatelessWidget {
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
          scrollDirection: .horizontal,
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

class const _CodexFileChip({
  super.key,
  required final String path,
  required final String displayName,
  required final bool isImage,
  required final bool isDirectory,
  required final VoidCallback onRemove,
  required final Future<void> Function() onOpen,
}) extends StatelessWidget {
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
      mainAxisSize: .min,
      children: <Widget>[
        Flexible(
          child: InkWell(
            onTap: () => unawaited(onOpen()),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: .circular(AleraTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space4,
                AleraTokens.space4,
                AleraTokens.space6,
                AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: .min,
                children: <Widget>[
                  if (isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                      child: Image.file(
                        File(path),
                        width: AleraTokens.codexAttachmentPreviewSize,
                        height: AleraTokens.codexAttachmentPreviewSize,
                        fit: .cover,
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
                      overflow: .ellipsis,
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

class const _CodexFailure({
  required final String message,
  required final Future<void> Function() onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AleraTokens.emptyStateMaxWidth,
      ),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          Text(message, textAlign: .center),
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

class const _CodexInlineError({
  required final String message,
  required final Future<void> Function() onRetry,
}) extends StatelessWidget {
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
