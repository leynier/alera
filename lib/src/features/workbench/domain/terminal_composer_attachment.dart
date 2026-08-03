import 'package:path/path.dart' as p;

enum TerminalComposerAttachmentKind { image, file }

final class TerminalComposerAttachment {
  const TerminalComposerAttachment({
    required this.id,
    required this.kind,
    required this.path,
    required this.displayName,
  });

  final String id;
  final TerminalComposerAttachmentKind kind;
  final String path;
  final String displayName;
}

TerminalComposerAttachmentKind terminalComposerAttachmentKindForPath(
  String path,
) {
  final extension = p.extension(path).toLowerCase();
  return const <String>{
        '.gif',
        '.jpeg',
        '.jpg',
        '.png',
        '.webp',
      }.contains(extension)
      ? TerminalComposerAttachmentKind.image
      : TerminalComposerAttachmentKind.file;
}
