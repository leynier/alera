import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/presentation/widgets/image_zoom_dialog.dart';
import 'package:alera/src/shared/utils/file_utils.dart';
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
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: 28,
        child: Builder(
          builder: (context) {
            final sorted = List<ComposerAttachment>.of(attachments)
              ..sort((a, b) {
                final aIsImage = a.kind == AttachmentKind.image ? 0 : 1;
                final bIsImage = b.kind == AttachmentKind.image ? 0 : 1;
                return aIsImage.compareTo(bIsImage);
              });
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sorted.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AleraTokens.space4),
              itemBuilder: (context, index) {
                final att = sorted[index];
                return _AttachmentChip(
                  attachment: att,
                  onRemove: () => onRemove(att.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final ComposerAttachment attachment;
  final VoidCallback onRemove;

  Widget _buildLabel(BuildContext context, bool isImage) {
    final label = Padding(
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
    );
    return GestureDetector(
      onTap: () => isImage
          ? showImageZoomDialog(context, attachment.path)
          : openFileNative(attachment.path),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.kind == AttachmentKind.image;
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isImage)
            GestureDetector(
              onTap: () => showImageZoomDialog(context, attachment.path),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AleraTokens.radiusXl),
                    bottomLeft: Radius.circular(AleraTokens.radiusXl),
                  ),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Image.file(
                      File(attachment.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image,
                        size: 14,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => openFileNative(attachment.path),
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: EdgeInsets.only(left: AleraTokens.space8),
                  child: Icon(
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ),
          _buildLabel(context, isImage),
          InkWell(
            onTap: onRemove,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
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
