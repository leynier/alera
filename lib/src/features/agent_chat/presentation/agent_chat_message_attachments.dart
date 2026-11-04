import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_attachment_previews.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

const double _thumbSize = 96;
const double _singleHeight = 160;
const double _mediaWidth = 320;
const double _cardWidth = 256;

/// A sent message's attachments, above its bubble: images and video as
/// thumbnails, snapshots whole and smaller, then pasted text and other files
/// as compact cards. A thumbnail reads the image from this machine when it
/// can: the file the person picked, or the host's copy when the host is this
/// machine. Otherwise an uploaded image of [chat] is read from its host
/// (`agentChatAttachmentReadV1`); until then, and when that is impossible,
/// it shows a placeholder tile with its name.
class const AgentChatMessageAttachmentsView({
  super.key,
  required final List<AgentChatAttachment> attachments,

  /// The chat the attachments were sent to, for reading them from its host.
  final AgentChatRef? chat,

  /// The chat's working directory, for relative host paths.
  final String? workspacePath,
  final ValueChanged<AgentChatAttachment>? onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final split = AgentChatMessageAttachments(attachments);
    final images = split.media.where(
      (attachment) => agentChatAttachmentShape(attachment) == .image,
    );
    final single = images.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: AleraTokens.space6,
      children: <Widget>[
        if (split.media.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _mediaWidth),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space4,
              runSpacing: AleraTokens.space4,
              children: <Widget>[
                for (final (index, attachment) in split.media.indexed)
                  _tap(
                    attachment,
                    _MediaTile(
                      key: ValueKey<String>('agent-chat-media-$index'),
                      attachment: attachment,
                      file: _localFile(attachment),
                      chat: chat,
                      single: single,
                    ),
                  ),
              ],
            ),
          ),
        if (split.cards.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final (index, attachment) in split.cards.indexed)
                _tap(
                  attachment,
                  AgentChatFileCard(
                    key: ValueKey<String>('agent-chat-file-card-$index'),
                    attachment: attachment,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _tap(AgentChatAttachment attachment, Widget child) {
    final open = onOpen;
    if (open == null || attachment.path == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => open(attachment), child: child),
    );
  }

  String? _localFile(AgentChatAttachment attachment) {
    final local = attachment.localSourcePath;
    if (local != null) return local;
    final path = attachment.path;
    if (path == null) return null;
    if (p.isAbsolute(path)) return path;
    final root = workspacePath;
    return root == null ? null : p.join(root, path);
  }
}

class const _MediaTile({
  super.key,
  required final AgentChatAttachment attachment,
  required final String? file,
  required final AgentChatRef? chat,
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
    final placeholder = _Placeholder(
      icon: shape == .video ? AleraIcons.play : AleraIcons.viewImage,
      name: attachment.displayName,
      width: width ?? _thumbSize,
      height: height,
    );
    final path = file;
    final fit = snapshot ? BoxFit.contain : BoxFit.cover;
    final host = chat;
    final remote = host == null || !agentChatAttachmentHostReadable(attachment)
        ? placeholder
        : _HostImage(
            chat: host,
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
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: shape == .video
            ? placeholder
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: snapshot
                      ? Border.all(color: AleraTokens.borderSubtle)
                      : null,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                ),
                child: path == null
                    ? remote
                    : Image.file(
                        File(path),
                        width: width,
                        height: height,
                        fit: fit,
                        cacheHeight: (height * 2).round(),
                        // A host path that is not on this machine.
                        errorBuilder: (_, _, _) => remote,
                      ),
              ),
      ),
    );
  }
}

/// An uploaded image read from the chat's host, or [placeholder] while it
/// loads and when the host cannot serve it.
class const _HostImage({
  required final AgentChatRef chat,
  required final String attachmentId,
  required final double? width,
  required final double height,
  required final BoxFit fit,
  required final Widget placeholder,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = agentChatAttachmentCacheKey(
      chat.workspaceId,
      chat.chatId,
      attachmentId,
    );
    final image =
        ref.watch(agentChatAttachmentCacheProvider).peek(key) ??
        ref
            .watch(
              agentChatAttachmentPreviewProvider(
                chat.chatId,
                chat.workspaceId,
                attachmentId,
              ),
            )
            .value;
    if (image == null) return placeholder;
    return Image(
      key: ValueKey<String>('agent-chat-host-image-$attachmentId'),
      image: ResizeImage(
        MemoryImage(image.bytes),
        height: (height * 2).round(),
        policy: ResizeImagePolicy.fit,
      ),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class const _Placeholder({
  required final IconData icon,
  required final String name,
  required final double width,
  required final double height,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(AleraTokens.space6),
    color: AleraTokens.surface,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          icon,
          size: AleraTokens.iconMd,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(height: AleraTokens.space4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AleraTokens.labelMicroFaintStyle,
        ),
      ],
    ),
  );
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
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: AleraTokens.space32,
            height: AleraTokens.space32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AleraTokens.bg,
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
                    size: AleraTokens.iconMd,
                  ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  agentChatAttachmentTitle(attachment),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  agentChatAttachmentSubtitle(attachment),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AleraTokens.labelMicroFaintStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
