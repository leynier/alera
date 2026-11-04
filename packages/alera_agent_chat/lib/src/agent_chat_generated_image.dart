import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';

/// The largest generated image the runtime serves.
const int agentChatGeneratedImageMaxBytes = 16 * 1024 * 1024;

/// The most one `agentChat.generatedImage` piece carries. Base64 adds a
/// third, which keeps a piece inside the phone relay's 1 MiB envelope.
const int agentChatGeneratedImageChunkBytes = 256 * 1024;

/// The image types the runtime serves; it checks each file's magic bytes.
const Set<String> agentChatGeneratedImageMimeTypes = <String>{
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

/// One piece of an image a provider generated (`agentChat.generatedImage`).
/// [contentToken] names the file's version, so pieces of a file that changed
/// between reads are never stitched together.
final class AgentChatGeneratedImageChunk {
  AgentChatGeneratedImageChunk._({
    required this.itemId,
    required this.mimeType,
    required this.sizeBytes,
    required this.offset,
    required this.nextOffset,
    required this.contentToken,
    required this.bytes,
  });

  /// Throws a [FormatException] for any answer outside the contract.
  factory AgentChatGeneratedImageChunk.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final itemId = agentChatJsonString(json['itemId']);
    final mimeType = json['mimeType'];
    final size = json['sizeBytes'];
    final offset = json['offset'];
    final next = json['nextOffset'];
    final token = agentChatJsonString(json['contentToken']);
    final data = json['dataBase64'];
    if (itemId == null || token == null || data is! String) {
      throw const FormatException('Invalid generated image piece.');
    }
    if (mimeType is! String ||
        !agentChatGeneratedImageMimeTypes.contains(mimeType)) {
      throw const FormatException('The generated image type is unsupported.');
    }
    if (size is! int || size <= 0 || size > agentChatGeneratedImageMaxBytes) {
      throw const FormatException('The generated image is too large.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const FormatException('Invalid generated image data.');
    }
    if (offset is! int ||
        offset < 0 ||
        bytes.length > agentChatGeneratedImageChunkBytes ||
        offset + bytes.length > size) {
      throw const FormatException('Invalid generated image range.');
    }
    final end = offset + bytes.length;
    // The last piece may name no next offset.
    if (next == null ? end != size : next != end) {
      throw const FormatException('Invalid generated image cursor.');
    }
    return AgentChatGeneratedImageChunk._(
      itemId: itemId,
      mimeType: mimeType,
      sizeBytes: size,
      offset: offset,
      nextOffset: end,
      contentToken: token,
      bytes: bytes,
    );
  }

  final String itemId;
  final String mimeType;
  final int sizeBytes;
  final int offset;

  /// Where the next piece starts; [sizeBytes] after the last one.
  final int nextOffset;
  final String contentToken;
  final Uint8List bytes;

  bool get isLast => nextOffset == sizeBytes;
}

/// An image a provider generated, read in full from the host.
final class AgentChatGeneratedImage {
  AgentChatGeneratedImage._({
    required this.itemId,
    required this.mimeType,
    required this.contentToken,
    required this.bytes,
  });

  final String itemId;
  final String mimeType;
  final String contentToken;
  final Uint8List bytes;
}

/// Reads the image the `image_generation` item [itemId] saved, piece by
/// piece (`agentChatGeneratedImagesV1`). Throws a [FormatException] when the
/// file changed between pieces, outgrows [agentChatGeneratedImageMaxBytes],
/// or its bytes are not the image type it claims.
Future<AgentChatGeneratedImage> loadAgentChatGeneratedImage(
  AgentChatLifecycleRepository repository,
  AgentChatRef chat, {
  required String itemId,
}) async {
  final builder = BytesBuilder(copy: false);
  AgentChatGeneratedImageChunk? first;
  var offset = 0;
  while (true) {
    final chunk = await repository.generatedImage(
      chat,
      itemId: itemId,
      offset: offset,
      length: agentChatGeneratedImageChunkBytes,
    );
    if (chunk.itemId != itemId || chunk.offset != offset) {
      throw const FormatException('Invalid generated image piece.');
    }
    if (first != null &&
        (chunk.contentToken != first.contentToken ||
            chunk.sizeBytes != first.sizeBytes ||
            chunk.mimeType != first.mimeType)) {
      throw const FormatException('The generated image changed while loading.');
    }
    first ??= chunk;
    builder.add(chunk.bytes);
    if (chunk.isLast) break;
    if (chunk.bytes.isEmpty) {
      throw const FormatException('Invalid generated image cursor.');
    }
    offset = chunk.nextOffset;
  }
  final bytes = builder.takeBytes();
  if (agentChatImageMimeType(bytes) != first.mimeType) {
    throw const FormatException('The generated image is not a valid image.');
  }
  return AgentChatGeneratedImage._(
    itemId: itemId,
    mimeType: first.mimeType,
    contentToken: first.contentToken,
    bytes: bytes,
  );
}

/// The image type [bytes] start with, by magic bytes, or null.
String? agentChatImageMimeType(List<int> bytes) {
  bool startsWith(List<int> magic, [int at = 0]) {
    if (bytes.length < at + magic.length) return false;
    for (var index = 0; index < magic.length; index += 1) {
      if (bytes[at + index] != magic[index]) return false;
    }
    return true;
  }

  if (startsWith(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(const <int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    return 'image/gif';
  }
  if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
    return 'image/webp';
  }
  return null;
}
