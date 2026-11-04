import 'dart:convert';

import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// Streams bounded chunks to the chat's owner, including through a paired hub.
/// Keep [uploadId] and the unchanged source for retry after connection loss.
final class AgentChatAttachmentUploader {
  const AgentChatAttachmentUploader(this.transport);

  final AgentChatTransport transport;
  static const int maxFileBytes = 32 * 1024 * 1024;
  static const int maxChunkBytes = 256 * 1024;

  Future<AgentChatAttachment> upload({
    required AgentChatRef chat,
    required String uploadId,
    required AgentChatAttachmentType type,
    required String name,
    required int sizeBytes,
    required Stream<List<int>> Function(int offset) openRead,
    String? sourceDigest,
    void Function(int uploadedBytes, int totalBytes)? onProgress,
  }) async {
    if (sizeBytes <= 0 ||
        sizeBytes > maxFileBytes ||
        type == AgentChatAttachmentType.image) {
      throw const FormatException(
        'Chat attachments must contain 1 to 33554432 bytes and use a local file or image.',
      );
    }
    if (!await transport.supportsCapability(
      AgentChatWire.attachmentUploadCapability,
    )) {
      throw const AgentChatCapabilityRequired(
        AgentChatWire.attachmentUploadCapability,
      );
    }
    final scope = <String, Object?>{
      'workspaceId': chat.workspaceId,
      'chatId': chat.chatId,
      'uploadId': uploadId,
    };
    final started = await transport.request(
      AgentChatWire.attachmentStart,
      <String, Object?>{
        ...scope,
        'type': type.wire,
        'name': name,
        'sizeBytes': sizeBytes,
        'sourceDigest': ?sourceDigest,
      },
    );
    final chunkBytes = started['chunkBytes'];
    final initialOffset = started['offset'];
    final completed = started['complete'];
    if (started['uploadId'] != uploadId ||
        chunkBytes is! int ||
        chunkBytes <= 0 ||
        chunkBytes > maxChunkBytes ||
        initialOffset is! int ||
        initialOffset < 0 ||
        initialOffset > sizeBytes ||
        completed is! bool ||
        (completed && initialOffset != sizeBytes)) {
      throw const FormatException(
        'Invalid chat attachment upload reservation.',
      );
    }
    var offset = initialOffset;
    onProgress?.call(offset, sizeBytes);
    if (!completed) {
      await for (final event in openRead(offset)) {
        var position = 0;
        while (position < event.length) {
          final remaining = event.length - position;
          final length = remaining < chunkBytes ? remaining : chunkBytes;
          if (offset + length > sizeBytes) {
            throw const FormatException(
              'The attachment changed or exceeds its declared size.',
            );
          }
          final chunk = event.sublist(position, position + length);
          final result = await transport.request(
            AgentChatWire.attachmentChunk,
            <String, Object?>{
              ...scope,
              'offset': offset,
              'dataBase64': base64Encode(chunk),
            },
          );
          if (result['nextOffset'] != offset + length) {
            throw const FormatException(
              'Invalid chat attachment upload cursor.',
            );
          }
          offset += length;
          position += length;
          onProgress?.call(offset, sizeBytes);
        }
      }
      if (offset != sizeBytes) {
        throw const FormatException(
          'The attachment changed or ended before its declared size.',
        );
      }
    }
    final receipt = await transport.request(
      AgentChatWire.attachmentComplete,
      scope,
    );
    final attachment = AgentChatAttachment.fromJson(receipt);
    if (attachment.attachmentId != uploadId ||
        attachment.path == null ||
        attachment.path!.isEmpty ||
        attachment.type != type ||
        attachment.sizeBytes != sizeBytes) {
      throw const FormatException('Invalid completed chat attachment receipt.');
    }
    return attachment;
  }

  Future<void> cancel({
    required AgentChatRef chat,
    required String uploadId,
  }) async {
    await transport.request(AgentChatWire.attachmentCancel, <String, Object?>{
      'workspaceId': chat.workspaceId,
      'chatId': chat.chatId,
      'uploadId': uploadId,
    });
  }
}
