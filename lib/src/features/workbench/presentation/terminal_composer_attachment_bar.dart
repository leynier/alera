import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_image_preview.dart';
import 'package:flutter/material.dart';

class TerminalComposerAttachmentBar extends StatelessWidget {
  const TerminalComposerAttachmentBar({
    super.key,
    required this.attachments,
    required this.onRemove,
    required this.onOpenFile,
    this.enabled = true,
  });

  final List<TerminalComposerAttachment> attachments;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onOpenFile;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    final sortedAttachments = List<TerminalComposerAttachment>.of(attachments)
      ..sort((a, b) => _kindOrder(a.kind).compareTo(_kindOrder(b.kind)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: AleraTokens.space32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: sortedAttachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final attachment = sortedAttachments[index];
            return _TerminalComposerAttachmentChip(
              attachment: attachment,
              onRemove: () => onRemove(attachment.id),
              onOpenFile: () => onOpenFile(attachment.path),
              enabled: enabled,
            );
          },
        ),
      ),
    );
  }

  int _kindOrder(TerminalComposerAttachmentKind kind) =>
      kind == TerminalComposerAttachmentKind.image ? 0 : 1;
}

class _TerminalComposerAttachmentChip extends StatelessWidget {
  const _TerminalComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
    required this.onOpenFile,
    required this.enabled,
  });

  final TerminalComposerAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback onOpenFile;
  final bool enabled;

  void _open(BuildContext context) {
    if (attachment.kind == TerminalComposerAttachmentKind.image) {
      showTerminalComposerImagePreview(context, attachment.path);
      return;
    }
    onOpenFile();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey<String>('terminal-composer-attachment-${attachment.id}'),
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: attachment.kind == TerminalComposerAttachmentKind.image
                ? 'View Image'
                : 'Open File',
            child: Semantics(
              button: true,
              label: attachment.kind == TerminalComposerAttachmentKind.image
                  ? 'View Image ${attachment.displayName}'
                  : 'Open File ${attachment.displayName}',
              child: InkWell(
                key: ValueKey<String>(
                  'terminal-composer-attachment-open-${attachment.id}',
                ),
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _open(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (attachment.kind == TerminalComposerAttachmentKind.image)
                      SizedBox(
                        width: AleraTokens.space32,
                        height: AleraTokens.space32,
                        child: Image.file(
                          File(attachment.path),
                          fit: BoxFit.cover,
                          cacheWidth: (AleraTokens.space32 * 2).round(),
                          errorBuilder: (_, _, _) => const Icon(
                            AleraIcons.imageError,
                            size: AleraTokens.space16,
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      )
                    else
                      const SizedBox(
                        width: AleraTokens.space32,
                        height: AleraTokens.space32,
                        child: Icon(
                          AleraIcons.fileGeneric,
                          size: AleraTokens.space16,
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AleraTokens.masterDetailMinWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space6,
                        ),
                        child: Text(
                          attachment.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AleraTokens.foregroundMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AleraIconButton(
            key: ValueKey<String>(
              'terminal-composer-attachment-remove-${attachment.id}',
            ),
            tooltip: attachment.kind == TerminalComposerAttachmentKind.image
                ? 'Remove Image'
                : 'Remove File',
            icon: AleraIcons.close,
            iconSize: AleraTokens.space12,
            minSize: AleraTokens.space24,
            onPressed: enabled ? onRemove : null,
          ),
          const SizedBox(width: AleraTokens.space4),
        ],
      ),
    );
  }
}
