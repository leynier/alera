import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_attachment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Which attachment sources the paired runtime serves for one chat.
class const AgentChatAttachmentSources({
  final MobileWorkspaceClient? images,
  final MobileCodexWorkspaceClient? files,
  final MobileCodexWorkspaceClient? workspaceFiles,
  final AgentChatAttachmentUploader? uploads,
}) {
  /// New hosts route uploads to the chat owner. Older hosts retain paired
  /// host uploads for workspaces that live on that host.
  factory read(WidgetRef ref, String hostId, {required bool remoteWorkspace}) {
    final Object? client = ref.read(workspaceClientProvider(hostId)).value;
    final legacyUploads = !remoteWorkspace;
    return AgentChatAttachmentSources(
      uploads:
          client is MobileAgentChatClient &&
              client.runtimeCapabilities.contains(
                AgentChatWire.attachmentUploadCapability,
              )
          ? AgentChatAttachmentUploader(MobileAgentChatTransport(client))
          : null,
      images:
          legacyUploads &&
              client is MobileWorkspaceClient &&
              client.supportsPromptImageUpload
          ? client
          : null,
      files:
          legacyUploads &&
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

  bool get isEmpty =>
      images == null &&
      files == null &&
      workspaceFiles == null &&
      uploads == null;
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
  void Function(bool uploading)? onUploadingChanged,
  void Function(int uploadedBytes, int totalBytes)? onProgress,
  VoidCallback? onUploadFailed,
}) async {
  final store = ref.read(agentChatDraftStoreProvider);
  final imagePicker = ref.read(promptImagePickerProvider);
  final filePicker = ref.read(promptFilePickerProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final source = await showPromptAttachmentSheet(
    context,
    allowPhotoLibrary: sources.images != null || sources.uploads != null,
    allowFiles: sources.files != null || sources.uploads != null,
    allowWorkspaceFile: sources.workspaceFiles != null,
  );
  if (source == null || !context.mounted) return;
  void add(AgentChatDraftAttachment attachment) =>
      store.addAttachment(hostId, chatId, attachment, workspaceId: workspaceId);
  Future<AgentChatAttachment> upload({
    required String name,
    required int sizeBytes,
    required AgentChatAttachmentType type,
    required Stream<List<int>> Function() openRead,
  }) => sources.uploads!.upload(
    chat: AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    uploadId: const Uuid().v4(),
    type: type,
    name: name,
    sizeBytes: sizeBytes,
    openRead: (offset) => _resumeSource(openRead(), offset),
    onProgress: onProgress,
  );
  try {
    switch (source) {
      case PromptAttachmentSource.photoLibrary:
        for (final image in await imagePicker.pickImages()) {
          onUploadingChanged?.call(true);
          if (sources.uploads != null) {
            final result = await upload(
              name: image.name,
              sizeBytes: image.sizeBytes,
              type: .localImage,
              openRead: image.openRead,
            );
            add(
              AgentChatDraftAttachment(
                path: result.path!,
                source: .image,
                displayName: image.name,
                attachmentId: result.attachmentId,
                sizeBytes: result.sizeBytes,
              ),
            );
            continue;
          }
          final result = await sources.images!.uploadPromptImage(
            format: promptImageFormatForFileName(image.name),
            sizeBytes: image.sizeBytes,
            openRead: image.openRead,
          );
          add(
            AgentChatDraftAttachment(
              path: result.hostPath,
              source: .image,
              displayName: image.name,
            ),
          );
        }
      case PromptAttachmentSource.files:
        final file = await filePicker.pickFile();
        if (file == null) return;
        onUploadingChanged?.call(true);
        if (sources.uploads != null) {
          final result = await upload(
            name: file.name,
            sizeBytes: file.sizeBytes,
            type: .file,
            openRead: file.openRead,
          );
          add(
            AgentChatDraftAttachment(
              path: result.path!,
              source: .file,
              displayName: file.name,
              attachmentId: result.attachmentId,
              sizeBytes: result.sizeBytes,
            ),
          );
          break;
        }
        final result = await sources.files!.uploadPromptFile(
          name: file.name,
          sizeBytes: file.sizeBytes,
          openRead: file.openRead,
        );
        add(
          AgentChatDraftAttachment(
            path: result.hostPath,
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
  } on Object catch (error) {
    onUploadFailed?.call();
    Logger('AgentChatAttachments').warning('Attachment upload failed.');
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error is UnsupportedError
              ? error.message ?? 'Attachment failed.'
              : 'Could not upload the attachment. Try again.',
        ),
      ),
    );
  } finally {
    onUploadingChanged?.call(false);
  }
}

Stream<List<int>> _resumeSource(Stream<List<int>> stream, int offset) async* {
  var remaining = offset;
  await for (final bytes in stream) {
    if (remaining >= bytes.length) {
      remaining -= bytes.length;
      continue;
    }
    yield remaining == 0 ? bytes : bytes.sublist(remaining);
    remaining = 0;
  }
}
