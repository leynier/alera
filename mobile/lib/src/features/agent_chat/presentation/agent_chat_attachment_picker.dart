import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_attachment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// Which attachment sources the paired runtime serves for one chat.
class const AgentChatAttachmentSources({
  final MobileWorkspaceClient? images,
  final MobileCodexWorkspaceClient? files,
  final MobileCodexWorkspaceClient? workspaceFiles,
}) {
  /// Uploads land on the paired device, so a chat in a workspace on another
  /// host only offers files that already live in that workspace.
  factory read(WidgetRef ref, String hostId, {required bool remoteWorkspace}) {
    final Object? client = ref.read(workspaceClientProvider(hostId)).value;
    final uploads = !remoteWorkspace;
    return AgentChatAttachmentSources(
      images:
          uploads &&
              client is MobileWorkspaceClient &&
              client.supportsPromptImageUpload
          ? client
          : null,
      files:
          uploads &&
              client is MobileCodexWorkspaceClient &&
              client.supportsPromptFileUpload
          ? client
          : null,
      workspaceFiles:
          client is MobileCodexWorkspaceClient &&
              client.supportsCodexWorkspaceFiles
          ? client
          : null,
    );
  }

  bool get isEmpty => images == null && files == null && workspaceFiles == null;
}

/// Picks and uploads attachments for a chat's composer.
///
/// Everything the upload needs is captured before the first await: picking
/// backgrounds the app, the chat body may be rebuilt meanwhile, and the
/// finished upload lands in the draft store for whichever composer is shown.
Future<void> pickAgentChatAttachments(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required String workspaceId,
  required String chatId,
  required AgentChatAttachmentSources sources,
}) async {
  final store = ref.read(agentChatDraftStoreProvider);
  final imagePicker = ref.read(promptImagePickerProvider);
  final filePicker = ref.read(promptFilePickerProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final source = await showPromptAttachmentSheet(
    context,
    allowPhotoLibrary: sources.images != null,
    allowFiles: sources.files != null,
    allowWorkspaceFile: sources.workspaceFiles != null,
  );
  if (source == null || !context.mounted) return;
  void add(AgentChatDraftAttachment attachment) =>
      store.addAttachment(hostId, chatId, attachment);
  try {
    switch (source) {
      case PromptAttachmentSource.photoLibrary:
        final client = sources.images!;
        for (final image in await imagePicker.pickImages()) {
          final upload = await client.uploadPromptImage(
            format: promptImageFormatForFileName(image.name),
            sizeBytes: image.sizeBytes,
            openRead: image.openRead,
          );
          add(
            AgentChatDraftAttachment(
              path: upload.hostPath,
              source: .image,
              displayName: image.name,
            ),
          );
        }
      case PromptAttachmentSource.files:
        final file = await filePicker.pickFile();
        if (file == null) return;
        final upload = await sources.files!.uploadPromptFile(
          name: file.name,
          sizeBytes: file.sizeBytes,
          openRead: file.openRead,
        );
        add(
          AgentChatDraftAttachment(
            path: upload.hostPath,
            source: .file,
            displayName: file.name,
          ),
        );
      case PromptAttachmentSource.workspaceFile:
        final client = sources.workspaceFiles!;
        final path = await showWorkspaceFilePickerSheet(
          context,
          start: () => client.startWorkspaceQuickOpen(workspaceId),
          search: client.searchWorkspaceQuickOpen,
          stop: client.stopWorkspaceQuickOpen,
        );
        if (path == null) return;
        // Relative on purpose: the runtime resolves it against the chat's
        // working directory, which is the workspace.
        add(
          AgentChatDraftAttachment(
            path: path,
            source: .workspaceFile,
            displayName: path.split('/').last,
          ),
        );
    }
  } on Object catch (error, stackTrace) {
    Logger('AgentChatAttachments')
        .warning('Attachment failed.', error, stackTrace);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error is UnsupportedError
              ? error.message ?? 'Attachment failed.'
              : 'Attachment failed.',
        ),
      ),
    );
  }
}
