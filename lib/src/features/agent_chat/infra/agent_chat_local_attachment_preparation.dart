import 'dart:io';
import 'dart:isolate';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

final class const AgentChatLocalAttachmentSource({
  required final int sizeBytes,
  required final String digest,
  required final Stream<List<int>> Function(int offset) openRead,
});

/// Only an explicit device-local origin opens a file on this machine.
final class AgentChatLocalAttachmentPreparation {
  const AgentChatLocalAttachmentPreparation({
    required this.transport,
    required this.localWorkspace,
    this.loadSource = _loadSource,
  });

  final AgentChatTransport transport;
  final bool localWorkspace;
  final Future<AgentChatLocalAttachmentSource> Function(String) loadSource;

  Future<List<AgentChatAttachment>> prepare(
    AgentChatRef chat,
    List<AgentChatAttachment> attachments,
    String clientMessageId,
  ) async {
    if (!attachments.any(
      (attachment) =>
          attachment.localSourcePath != null && attachment.attachmentId == null,
    )) {
      return attachments;
    }
    if (!await transport.supportsCapability(
      AgentChatWire.attachmentUploadCapability,
    )) {
      if (localWorkspace) return attachments;
      throw const AgentChatCapabilityRequired(
        AgentChatWire.attachmentUploadCapability,
      );
    }
    final uploader = AgentChatAttachmentUploader(transport);
    final prepared = <AgentChatAttachment>[];
    for (var index = 0; index < attachments.length; index += 1) {
      final attachment = attachments[index];
      final path = attachment.localSourcePath;
      if (path == null || attachment.attachmentId != null) {
        prepared.add(attachment);
        continue;
      }
      final source = await loadSource(path);
      prepared.add(
        await uploader.upload(
          chat: chat,
          uploadId: const Uuid().v5(
            Namespace.url.value,
            '${chat.workspaceId}:${chat.chatId}:$clientMessageId:$index',
          ),
          type: attachment.type,
          name: attachment.displayName,
          sizeBytes: source.sizeBytes,
          sourceDigest: source.digest,
          openRead: source.openRead,
        ),
      );
    }
    return List<AgentChatAttachment>.unmodifiableOf(prepared);
  }
}

Future<AgentChatLocalAttachmentSource> _loadSource(String path) async {
  // Hashing can scan 32 MiB; the UI isolate only coordinates the upload.
  final fingerprint = await Isolate.run(() async {
    final file = File(path);
    final size = await file.length();
    if (size <= 0 || size > AgentChatAttachmentUploader.maxFileBytes) {
      throw const FormatException(
        'Chat attachments must contain 1 to 33554432 bytes.',
      );
    }
    return (size, (await sha256.bind(file.openRead()).first).toString());
  });
  return AgentChatLocalAttachmentSource(
    sizeBytes: fingerprint.$1,
    digest: fingerprint.$2,
    openRead: (offset) => File(path).openRead(offset),
  );
}
