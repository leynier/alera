import 'dart:convert';

import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';

final class const AgentChatPayloadChunk({
  required final int index,
  required final String text,
});

/// Retained redacted JSON text, with zero-based chunk indices.
final class AgentChatPayloadPage {
  AgentChatPayloadPage({
    required List<AgentChatPayloadChunk> chunks,
    required this.segmentCount,
    required this.revision,
    this.nextIndex,
  }) : chunks = List<AgentChatPayloadChunk>.unmodifiableOf(chunks);

  factory AgentChatPayloadPage.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final count = json['segmentCount'];
    final next = json['nextIndex'];
    final rawChunks = json['chunks'];
    final revision = json['revision'];
    if (json['format'] != 'json' ||
        count is! int ||
        count <= 0 ||
        revision is! String ||
        revision.isEmpty ||
        (next != null && (next is! int || next < 0)) ||
        rawChunks is! List ||
        rawChunks.isEmpty ||
        rawChunks.length > 200) {
      throw const FormatException('Invalid retained chat payload page.');
    }
    final chunks = <AgentChatPayloadChunk>[];
    for (final value in rawChunks) {
      final chunk = agentChatJsonMap(value);
      final index = chunk['index'];
      final text = chunk['text'];
      if (index is! int || index < 0 || index >= count || text is! String) {
        throw const FormatException('Invalid retained chat payload chunk.');
      }
      chunks.add(AgentChatPayloadChunk(index: index, text: text));
    }
    if (utf8.encode(jsonEncode(json)).length > 256 * 1024) {
      throw const FormatException(
        'Retained chat payload page exceeds its budget.',
      );
    }
    return AgentChatPayloadPage(
      chunks: chunks,
      segmentCount: count,
      revision: revision,
      nextIndex: next as int?,
    );
  }

  final List<AgentChatPayloadChunk> chunks;
  final int segmentCount;
  final String revision;
  final int? nextIndex;
  String get format => 'json';
}

/// Optional capability so existing repository implementations stay compatible.
abstract interface class AgentChatPayloadRepository {
  Future<AgentChatPayloadPage> payload(
    AgentChatRef chat, {
    required String itemId,
    int index = 0,
    int? limit,
  });
}

extension AgentChatPayloadLoading on AgentChatPayloadRepository {
  /// Loads text only when called explicitly; native JSON is never decoded here.
  Stream<AgentChatPayloadChunk> payloadChunks(
    AgentChatRef chat, {
    required String itemId,
    int? limit,
  }) async* {
    var index = 0;
    int? segmentCount;
    String? revision;
    while (true) {
      final page = await payload(
        chat,
        itemId: itemId,
        index: index,
        limit: limit,
      );
      if ((segmentCount != null && page.segmentCount != segmentCount) ||
          (revision != null && page.revision != revision)) {
        throw const FormatException(
          'Retained chat payload changed while loading.',
        );
      }
      segmentCount = page.segmentCount;
      revision = page.revision;
      for (final chunk in page.chunks) {
        if (chunk.index != index) {
          throw const FormatException(
            'Retained chat payload has missing segments.',
          );
        }
        yield chunk;
        index += 1;
      }
      final expectedNext = index < segmentCount ? index : null;
      if (page.nextIndex != expectedNext || index > segmentCount) {
        throw const FormatException('Invalid retained chat payload cursor.');
      }
      if (page.nextIndex == null) return;
    }
  }

  Future<String> loadPayloadJson(
    AgentChatRef chat, {
    required String itemId,
    int? limit,
  }) async {
    final text = StringBuffer();
    await for (final chunk in payloadChunks(
      chat,
      itemId: itemId,
      limit: limit,
    )) {
      text.write(chunk.text);
    }
    return text.toString();
  }
}
