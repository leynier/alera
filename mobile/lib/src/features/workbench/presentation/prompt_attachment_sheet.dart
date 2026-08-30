import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:flutter/material.dart';

/// Where a prompt attachment comes from.
enum PromptAttachmentSource { photoLibrary, files, workspaceFile }

/// Attachment source picker, shared by the Codex composer and the terminal.
///
/// A source the host cannot serve is omitted rather than disabled: an entry
/// that only ever reports an error is worse than an absent one.
Future<PromptAttachmentSource?> showPromptAttachmentSheet(
  BuildContext context, {
  required bool allowPhotoLibrary,
  required bool allowFiles,
  required bool allowWorkspaceFile,
}) {
  return showAleraActionSheet<PromptAttachmentSource>(
    context,
    entries: <AleraActionSheetEntry<PromptAttachmentSource>>[
      if (allowPhotoLibrary)
        const AleraActionSheetEntry<PromptAttachmentSource>(
          value: .photoLibrary,
          label: 'Photo Library',
          leading: Icon(Icons.image_outlined),
        ),
      if (allowFiles)
        const AleraActionSheetEntry<PromptAttachmentSource>(
          value: .files,
          label: 'Files',
          leading: Icon(Icons.attach_file),
        ),
      if (allowWorkspaceFile)
        const AleraActionSheetEntry<PromptAttachmentSource>(
          value: .workspaceFile,
          label: 'Workspace File',
          leading: Icon(Icons.folder_open_outlined),
        ),
    ],
  );
}
