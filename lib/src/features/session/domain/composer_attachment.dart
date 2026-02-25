enum AttachmentKind { file, image }

class ComposerAttachment {
  const ComposerAttachment({
    required this.id,
    required this.kind,
    required this.path,
    required this.displayName,
    this.mimeType,
    this.sizeBytes,
  });

  final String id;
  final AttachmentKind kind;
  final String path;
  final String displayName;
  final String? mimeType;
  final int? sizeBytes;
}
