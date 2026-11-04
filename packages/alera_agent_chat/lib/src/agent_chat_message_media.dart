import 'package:alera_agent_chat/src/agent_chat_item.dart';

/// How a sent attachment is drawn: images, video and snapshots as media
/// above the bubble, pasted text and other files as compact cards.
enum AgentChatAttachmentShape {
  image,
  video,

  /// A screenshot or window capture: shown whole, never cropped.
  snapshot,

  /// Text the composer turned into a file because it was pasted.
  pastedText,
  file;

  bool get isMedia => this == image || this == video || this == snapshot;
}

const Set<String> _imageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'avif',
};

const Set<String> _videoExtensions = <String>{
  'mp4',
  'mov',
  'm4v',
  'webm',
  'mkv',
  'avi',
};

const Set<String> _textExtensions = <String>{'', 'txt', 'md', 'log'};

AgentChatAttachmentShape agentChatAttachmentShape(
  AgentChatAttachment attachment,
) {
  final name = attachment.displayName.trim().toLowerCase();
  final mime = (attachment.mimeType ?? '').toLowerCase();
  final extension = agentChatAttachmentExtension(attachment).toLowerCase();
  if (mime.startsWith('video/') || _videoExtensions.contains(extension)) {
    return .video;
  }
  if (attachment.type.isImage ||
      mime.startsWith('image/') ||
      _imageExtensions.contains(extension)) {
    return name.startsWith('screenshot') ||
            name.startsWith('screen shot') ||
            name.startsWith('snapshot')
        ? .snapshot
        : .image;
  }
  if (name.startsWith('pasted') &&
      (mime.startsWith('text/') || _textExtensions.contains(extension))) {
    return .pastedText;
  }
  return .file;
}

/// The extension of the attachment's name (or path), without the dot; empty
/// when it has none.
String agentChatAttachmentExtension(AgentChatAttachment attachment) {
  final name = attachment.displayName;
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1 ? '' : name.substring(dot + 1);
}

/// A card's title: "Pasted text" for pasted text, the file name otherwise.
String agentChatAttachmentTitle(AgentChatAttachment attachment) =>
    agentChatAttachmentShape(attachment) == .pastedText
    ? 'Pasted text'
    : attachment.displayName;

/// A card's subtitle: "PDF · 1.2 MB", or the size alone for pasted text,
/// falling back to "File".
String agentChatAttachmentSubtitle(AgentChatAttachment attachment) {
  final size = attachment.sizeBytes;
  final sizeLabel = size == null ? null : agentChatByteLabel(size);
  if (agentChatAttachmentShape(attachment) == .pastedText) {
    return sizeLabel ?? 'Text';
  }
  final extension = agentChatAttachmentExtension(attachment).toUpperCase();
  final kind = extension.isEmpty || extension.length > 8 ? 'File' : extension;
  return sizeLabel == null ? kind : '$kind · $sizeLabel';
}

/// "512 B", "12 KB", "1.5 MB": a size rounded so it never reads "1024 KB".
String agentChatByteLabel(int bytes) {
  const units = <String>['KB', 'MB', 'GB', 'TB'];
  if (bytes < 1024) return '$bytes B';
  var value = bytes / 1024;
  var unit = 0;
  while (unit < units.length - 1 && value >= 1024) {
    value /= 1024;
    unit += 1;
  }
  var label = value < 10
      ? value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')
      : value.round().toString();
  if (label == '1024' && unit < units.length - 1) {
    label = '1';
    unit += 1;
  }
  return '$label ${units[unit]}';
}

/// A sent message's attachments split into media above the bubble and cards.
final class AgentChatMessageAttachments {
  AgentChatMessageAttachments(List<AgentChatAttachment> attachments)
    : media = <AgentChatAttachment>[
        for (final attachment in attachments)
          if (agentChatAttachmentShape(attachment).isMedia) attachment,
      ],
      cards = <AgentChatAttachment>[
        for (final attachment in attachments)
          if (!agentChatAttachmentShape(attachment).isMedia) attachment,
      ];

  final List<AgentChatAttachment> media;
  final List<AgentChatAttachment> cards;
}
