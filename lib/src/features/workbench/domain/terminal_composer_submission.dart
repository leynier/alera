import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:alera/src/features/workbench/domain/workspace_relative_path.dart';

String buildTerminalComposerSubmission({
  required String prompt,
  required Iterable<TerminalComposerAttachment> attachments,
  String? workspacePath,
}) {
  final images = <String>[];
  final files = <String>[];
  for (final attachment in attachments) {
    final path = sanitizeTerminalImagePastePath(attachment.path);
    if (path.isEmpty) {
      continue;
    }
    final submissionPath = workspacePath == null
        ? path
        : workspaceRelativePath(workspacePath: workspacePath, filePath: path) ??
              path;
    switch (attachment.kind) {
      case TerminalComposerAttachmentKind.image:
        images.add(submissionPath);
      case TerminalComposerAttachmentKind.file:
        files.add(submissionPath);
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
