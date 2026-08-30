import 'package:path/path.dart' as p;

enum TerminalComposerAttachmentKind { image, file }

final class const TerminalComposerAttachment({
  required final String id,
  required final TerminalComposerAttachmentKind kind,
  required final String path,
  required final String displayName,
});

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
