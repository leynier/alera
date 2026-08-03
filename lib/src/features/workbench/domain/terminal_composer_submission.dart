import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';

String buildTerminalComposerSubmission({
  required String prompt,
  required Iterable<TerminalComposerAttachment> attachments,
}) {
  final images = <String>[];
  final files = <String>[];
  for (final attachment in attachments) {
    final path = sanitizeTerminalImagePastePath(attachment.path);
    if (path.isEmpty) {
      continue;
    }
    switch (attachment.kind) {
      case TerminalComposerAttachmentKind.image:
        images.add(path);
      case TerminalComposerAttachmentKind.file:
        files.add(path);
    }
  }
  final sections = <String>[
    if (images.isNotEmpty) ...<String>['Attached images:', ...images],
    if (files.isNotEmpty) ...<String>['Attached files:', ...files],
  ];
  if (sections.isEmpty) {
    return prompt;
  }
  final attachmentText = sections.join('\n');
  if (prompt.trim().isEmpty) {
    return attachmentText;
  }
  return '$prompt\n\n$attachmentText';
}
