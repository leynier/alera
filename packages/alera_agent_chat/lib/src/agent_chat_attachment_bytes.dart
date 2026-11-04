import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_message_media.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// The largest attachment the host serves back (`agentChat.attachment.read`).
const int agentChatAttachmentReadMaxBytes = 8 * 1024 * 1024;

/// The most one `agentChat.attachment.read` piece carries. Base64 adds a
/// third, which keeps a piece inside the phone relay's 1 MiB envelope.
const int agentChatAttachmentReadChunkBytes = 256 * 1024;

/// How many attachment bytes the in-memory thumbnail cache keeps.
const int agentChatAttachmentCacheBytes = 32 * 1024 * 1024;

/// One piece of an uploaded image or video (`agentChat.attachment.read`).
final class AgentChatAttachmentChunk {
  AgentChatAttachmentChunk._({
    required this.attachmentId,
    required this.mimeType,
    required this.sizeBytes,
    required this.offset,
    required this.nextOffset,
    required this.bytes,
  });

  /// Throws a [FormatException] for any answer outside the contract.
  factory AgentChatAttachmentChunk.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['attachmentId']);
    final mimeType = json['mimeType'];
    final size = json['sizeBytes'];
    final offset = json['offset'];
    final next = json['nextOffset'];
    final data = json['dataBase64'];
    if (id == null || mimeType is! String || data is! String) {
      throw const FormatException('Invalid attachment piece.');
    }
    if (!mimeType.startsWith('image/') && !mimeType.startsWith('video/')) {
      throw const FormatException('The attachment is not an image or video.');
    }
    if (size is! int || size <= 0 || size > agentChatAttachmentReadMaxBytes) {
      throw const FormatException('The attachment is too large.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const FormatException('Invalid attachment data.');
    }
    if (offset is! int ||
        offset < 0 ||
        bytes.length > agentChatAttachmentReadChunkBytes ||
        offset + bytes.length > size ||
        next != offset + bytes.length) {
      throw const FormatException('Invalid attachment range.');
    }
    return AgentChatAttachmentChunk._(
      attachmentId: id,
      mimeType: mimeType,
      sizeBytes: size,
      offset: offset,
      nextOffset: offset + bytes.length,
      bytes: bytes,
    );
  }

  final String attachmentId;
  final String mimeType;
  final int sizeBytes;
  final int offset;

  /// Where the next piece starts; [sizeBytes] after the last one.
  final int nextOffset;
  final Uint8List bytes;

  bool get isLast => nextOffset == sizeBytes;
}

/// An uploaded attachment read whole from its host.
final class AgentChatAttachmentBytes {
  AgentChatAttachmentBytes._({
    required this.attachmentId,
    required this.mimeType,
    required this.bytes,
  });

  final String attachmentId;
  final String mimeType;
  final Uint8List bytes;
}

/// Reads the uploaded attachment [attachmentId] of [chat] piece by piece
/// (`agentChatAttachmentReadV1`). Throws a [FormatException] when the
/// pieces disagree or the answer leaves the contract.
Future<AgentChatAttachmentBytes> loadAgentChatAttachment(
  AgentChatLifecycleRepository repository,
  AgentChatRef chat, {
  required String attachmentId,
}) async {
  final builder = BytesBuilder(copy: false);
  AgentChatAttachmentChunk? first;
  var offset = 0;
  while (true) {
    final chunk = await repository.attachment(
      chat,
      attachmentId: attachmentId,
      offset: offset,
      length: agentChatAttachmentReadChunkBytes,
    );
    if (chunk.attachmentId != attachmentId || chunk.offset != offset) {
      throw const FormatException('Invalid attachment piece.');
    }
    if (first != null &&
        (chunk.sizeBytes != first.sizeBytes ||
            chunk.mimeType != first.mimeType)) {
      throw const FormatException('The attachment changed while loading.');
    }
    first ??= chunk;
    builder.add(chunk.bytes);
    if (chunk.isLast) break;
    if (chunk.bytes.isEmpty) {
      throw const FormatException('Invalid attachment cursor.');
    }
    offset = chunk.nextOffset;
  }
  return AgentChatAttachmentBytes._(
    attachmentId: attachmentId,
    mimeType: first.mimeType,
    bytes: builder.takeBytes(),
  );
}

/// Whether [attachment] is an uploaded image whose host copy a thumbnail
/// can read. Video stays a placeholder: thumbnails do not decode frames.
bool agentChatAttachmentHostReadable(AgentChatAttachment attachment) {
  final size = attachment.sizeBytes;
  final shape = agentChatAttachmentShape(attachment);
  return attachment.attachmentId != null &&
      (shape == .image || shape == .snapshot) &&
      (size == null || (size > 0 && size <= agentChatAttachmentReadMaxBytes));
}

/// A size-bounded, least-recently-used cache of attachment bytes, so a
/// thumbnail scrolled away and back is not read again. A load in flight is
/// shared by every reader; a failed load is not kept.
final class AgentChatAttachmentCache {
  AgentChatAttachmentCache({this.maxBytes = agentChatAttachmentCacheBytes});

  final int maxBytes;
  final LinkedHashMap<String, AgentChatAttachmentBytes> _entries =
      LinkedHashMap<String, AgentChatAttachmentBytes>();
  final Map<String, Future<AgentChatAttachmentBytes>> _loading =
      <String, Future<AgentChatAttachmentBytes>>{};
  int _bytes = 0;

  /// The bytes the cache holds now.
  int get sizeBytes => _bytes;

  /// The cached bytes for [key], marking them recently used.
  AgentChatAttachmentBytes? peek(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
    return entry;
  }

  /// The cached bytes for [key], or [fetch]ed and kept.
  Future<AgentChatAttachmentBytes> load(
    String key,
    Future<AgentChatAttachmentBytes> Function() fetch,
  ) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);
    return _loading[key] ??= () async {
      try {
        final value = await fetch();
        _store(key, value);
        return value;
      } finally {
        _loading.remove(key);
      }
    }();
  }

  void _store(String key, AgentChatAttachmentBytes value) {
    final size = value.bytes.length;
    if (size > maxBytes) return;
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.bytes.length;
    while (_entries.isNotEmpty && _bytes + size > maxBytes) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.bytes.length;
    }
    _entries[key] = value;
    _bytes += size;
  }
}

/// The host's copy of the uploaded image [attachmentId] of [chat] for a
/// thumbnail, through [cache] under [key], or null when the host cannot
/// serve it: no `agentChatAttachmentReadV1`, not an image, or a failed read.
/// Callers check [agentChatAttachmentHostReadable] first. Never throws.
Future<AgentChatAttachmentBytes?> fetchAgentChatAttachmentPreview(
  AgentChatLifecycleRepository repository,
  AgentChatRef chat, {
  required String attachmentId,
  required AgentChatAttachmentCache cache,
  required String key,
}) async {
  try {
    final cached = cache.peek(key);
    if (cached != null) return cached;
    if (!await repository.supports(AgentChatWire.attachmentReadCapability)) {
      return null;
    }
    final bytes = await cache.load(
      key,
      () =>
          loadAgentChatAttachment(repository, chat, attachmentId: attachmentId),
    );
    return bytes.mimeType.startsWith('image/') ? bytes : null;
  } on Object {
    return null;
  }
}
