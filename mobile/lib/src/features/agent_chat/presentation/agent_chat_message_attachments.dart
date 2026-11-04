import 'dart:io';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_attachment_previews.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _thumbSize = 96;
const double _singleHeight = 192;
const double _mediaWidth = 320;
const double _cardWidth = 256;

/// A sent message's attachments, above its bubble, as on desktop: images
/// and video as thumbnails, snapshots whole and smaller, then pasted text
/// and other files as compact cards. A thumbnail shows an image this phone
/// picked, or an uploaded image read from the chat's host through the relay
/// (`agentChatAttachmentReadV1`); until then, and when that is impossible,
/// it shows a placeholder tile with its name.
class const AgentChatMessageAttachmentsView({
  super.key,
  required final List<AgentChatAttachment> attachments,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final split = AgentChatMessageAttachments(attachments);
    final single =
        split.media
            .where(
              (attachment) => agentChatAttachmentShape(attachment) == .image,
            )
            .length ==
        1;
    return Column(
      crossAxisAlignment: .end,
      mainAxisSize: .min,
      spacing: AleraTokens.space6,
      children: <Widget>[
        if (split.media.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _mediaWidth),
            child: Wrap(
              alignment: .end,
              spacing: AleraTokens.space4,
              runSpacing: AleraTokens.space4,
              children: <Widget>[
                for (final (index, attachment) in split.media.indexed)
                  _MediaTile(
                    key: ValueKey<String>('agent-chat-media-$index'),
                    attachment: attachment,
                    single: single,
                  ),
              ],
            ),
          ),
        if (split.cards.isNotEmpty)
          Wrap(
            alignment: .end,
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final (index, attachment) in split.cards.indexed)
                AgentChatFileCard(
                  key: ValueKey<String>('agent-chat-file-card-$index'),
                  attachment: attachment,
                ),
            ],
          ),
      ],
    );
  }
}

class const _MediaTile({
  super.key,
  required final AgentChatAttachment attachment,
  required final bool single,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shape = agentChatAttachmentShape(attachment);
    final snapshot = shape == .snapshot;
    final (width, height) = switch (shape) {
      .video => (_singleHeight, _singleHeight * 0.75),
      _ when snapshot => (null, _thumbSize),
      _ when single => (null, _singleHeight),
      _ => (_thumbSize, _thumbSize),
    };
    final placeholder = Container(
      width: width ?? _thumbSize,
      height: height,
      padding: const EdgeInsets.all(AleraTokens.space6),
      color: AleraTokens.surfaceVariant,
      child: Column(
        mainAxisAlignment: .center,
        children: <Widget>[
          Icon(
            shape == .video ? AleraIcons.play : AleraIcons.viewImage,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            attachment.displayName,
            maxLines: 1,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        ],
      ),
    );
    final path = attachment.localSourcePath;
    final fit = snapshot ? BoxFit.contain : BoxFit.cover;
    final scope = AgentChatScope.maybeOf(context);
    final remote = scope == null || !agentChatAttachmentHostReadable(attachment)
        ? placeholder
        : _HostImage(
            scope: scope,
            attachmentId: attachment.attachmentId!,
            width: width,
            height: height,
            fit: fit,
            placeholder: placeholder,
          );
    return Semantics(
      image: true,
      label: attachment.displayName,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg * 2),
        child: shape == .video
            ? placeholder
            : path == null
            ? remote
            : Image.file(
                File(path),
                width: width,
                height: height,
                fit: fit,
                cacheHeight: (height * 3).round(),
                errorBuilder: (_, _, _) => remote,
              ),
      ),
    );
  }
}

/// An uploaded image read from the chat's host, or [placeholder] while it
/// loads and when the host cannot serve it.
class const _HostImage({
  required final AgentChatScope scope,
  required final String attachmentId,
  required final double? width,
  required final double height,
  required final BoxFit fit,
  required final Widget placeholder,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = agentChatAttachmentCacheKey(
      scope.hostId,
      scope.workspaceId,
      scope.chatId,
      attachmentId,
    );
    final image =
        ref.watch(agentChatAttachmentCacheProvider).peek(key) ??
        ref
            .watch(
              agentChatAttachmentPreviewProvider(
                scope.hostId,
                scope.workspaceId,
                scope.chatId,
                attachmentId,
              ),
            )
            .value;
    if (image == null) return placeholder;
    return Image(
      key: ValueKey<String>('agent-chat-host-image-$attachmentId'),
      image: ResizeImage(
        MemoryImage(image.bytes),
        height: (height * 3).round(),
        policy: ResizeImagePolicy.fit,
      ),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// A file sent with a message: its icon, its name ("Pasted text" for pasted
/// text) and "PDF · 1.2 MB".
class const AgentChatFileCard({
  super.key,
  required final AgentChatAttachment attachment,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pasted = agentChatAttachmentShape(attachment) == .pastedText;
    return Container(
      width: _cardWidth,
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg * 2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: AleraTokens.space32,
            height: AleraTokens.space32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AleraTokens.bg,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: pasted
                ? const Icon(
                    AleraIcons.paste,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundMuted,
                  )
                : AleraFileIcon(
                    pathOrName: attachment.displayName,
                    kind: AleraFileIconKind.file,
                  ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: <Widget>[
                Text(
                  agentChatAttachmentTitle(attachment),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  agentChatAttachmentSubtitle(attachment),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
