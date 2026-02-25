import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:flutter/material.dart';

class AttachmentBar extends StatelessWidget {
  const AttachmentBar({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<ComposerAttachment> attachments;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space4,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final att = attachments[index];
            return _AttachmentChip(
              attachment: att,
              onRemove: () => onRemove(att.id),
            );
          },
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final ComposerAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.kind == AttachmentKind.image;
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isImage)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AleraTokens.radiusSm),
                bottomLeft: Radius.circular(AleraTokens.radiusSm),
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Image.file(
                  File(attachment.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image,
                    size: 16,
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: AleraTokens.space6),
              child: Icon(
                Icons.insert_drive_file_outlined,
                size: 14,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
            child: Text(
              attachment.displayName,
              style: const TextStyle(
                fontSize: 11,
                color: AleraTokens.foregroundMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onRemove,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space4),
              child: Icon(
                Icons.close,
                size: 12,
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
