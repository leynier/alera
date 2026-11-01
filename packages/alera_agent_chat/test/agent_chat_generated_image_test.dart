import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List<int>.generate(300 * 1024, (index) => index % 251),
]);

/// Serves [bytes] in pieces as the runtime does.
final class _ImageTransport implements AgentChatTransport {
  _ImageTransport(this.bytes, {this.changeAfterFirst = false});

  final Uint8List bytes;
  final bool changeAfterFirst;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async => true;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    expect(type, AgentChatWire.generatedImage);
    requests.add(payload);
    final offset = payload['offset']! as int;
    final length = payload['length']! as int;
    final end = (offset + length).clamp(0, bytes.length);
    return <String, Object?>{
      'itemId': payload['itemId'],
      'mimeType': 'image/png',
      'sizeBytes': bytes.length,
      'offset': offset,
      'nextOffset': end,
      'contentToken': changeAfterFirst && offset > 0 ? 'v2' : 'v1',
      'dataBase64': base64Encode(bytes.sublist(offset, end)),
    };
  }
}

const _chat = AgentChatRef(chatId: 'chat-1', workspaceId: 'ws-1');

void main() {
  test('an image is read whole across pieces', () async {
    final transport = _ImageTransport(_png);
    final image = await loadAgentChatGeneratedImage(
      RuntimeAgentChatLifecycleRepository(transport),
      _chat,
      itemId: 'image-1',
    );
    expect(image.bytes, _png);
    expect(image.mimeType, 'image/png');
    expect(transport.requests, hasLength(2));
    expect(transport.requests.first['chatId'], 'chat-1');
    expect(
      transport.requests.last['offset'],
      agentChatGeneratedImageChunkBytes,
    );
  });

  test('a file that changed between pieces is refused', () async {
    await expectLater(
      loadAgentChatGeneratedImage(
        RuntimeAgentChatLifecycleRepository(
          _ImageTransport(_png, changeAfterFirst: true),
        ),
        _chat,
        itemId: 'image-1',
      ),
      throwsFormatException,
    );
  });

  test('pieces outside the contract are refused', () {
    Map<String, Object?> piece(Map<String, Object?> overrides) =>
        <String, Object?>{
          'itemId': 'image-1',
          'mimeType': 'image/png',
          'sizeBytes': 4,
          'offset': 0,
          'nextOffset': 4,
          'contentToken': 'v1',
          'dataBase64': base64Encode(<int>[1, 2, 3, 4]),
          ...overrides,
        };
    expect(AgentChatGeneratedImageChunk.fromJson(piece({})).isLast, isTrue);
    for (final bad in <Map<String, Object?>>[
      {'mimeType': 'image/svg+xml'},
      {'sizeBytes': agentChatGeneratedImageMaxBytes + 1},
      {'nextOffset': 3},
      {'offset': -1},
      {'dataBase64': '%%%'},
    ]) {
      expect(
        () => AgentChatGeneratedImageChunk.fromJson(piece(bad)),
        throwsFormatException,
        reason: '$bad',
      );
    }
    expect(agentChatImageMimeType(utf8.encode('GIF89a')), 'image/gif');
    expect(agentChatImageMimeType(utf8.encode('<svg')), isNull);
  });
}
