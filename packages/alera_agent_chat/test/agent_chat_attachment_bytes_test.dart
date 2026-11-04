import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List<int>.generate(300 * 1024, (index) => index % 251),
]);

/// Serves [bytes] in pieces as the runtime does.
final class _AttachmentTransport implements AgentChatTransport {
  _AttachmentTransport(
    this.bytes, {
    this.supported = true,
    this.mimeType = 'image/png',
  });

  final Uint8List bytes;
  final bool supported;
  final String mimeType;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async =>
      supported && capability == AgentChatWire.attachmentReadCapability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    expect(type, AgentChatWire.attachmentRead);
    requests.add(payload);
    final offset = payload['offset']! as int;
    final length = payload['length']! as int;
    final end = (offset + length).clamp(0, bytes.length);
    return <String, Object?>{
      'attachmentId': payload['attachmentId'],
      'mimeType': mimeType,
      'sizeBytes': bytes.length,
      'offset': offset,
      'nextOffset': end,
      'dataBase64': base64Encode(bytes.sublist(offset, end)),
    };
  }
}

const _chat = AgentChatRef(chatId: 'chat-1', workspaceId: 'ws-1');

Future<AgentChatAttachmentBytes> _load(Uint8List bytes, String id) =>
    loadAgentChatAttachment(
      RuntimeAgentChatLifecycleRepository(_AttachmentTransport(bytes)),
      _chat,
      attachmentId: id,
    );

void main() {
  test('an attachment is read whole across pieces', () async {
    final transport = _AttachmentTransport(_png);
    final read = await loadAgentChatAttachment(
      RuntimeAgentChatLifecycleRepository(transport),
      _chat,
      attachmentId: 'a-1',
    );
    expect(read.bytes, _png);
    expect(read.mimeType, 'image/png');
    expect(transport.requests, hasLength(2));
    expect(transport.requests.first['chatId'], 'chat-1');
    expect(transport.requests.first['workspaceId'], 'ws-1');
    expect(transport.requests.first['attachmentId'], 'a-1');
    expect(
      transport.requests.last['offset'],
      agentChatAttachmentReadChunkBytes,
    );
  });

  test('a piece outside the contract is refused', () {
    Object? piece(Map<String, Object?> change) => <String, Object?>{
      'attachmentId': 'a-1',
      'mimeType': 'image/png',
      'sizeBytes': 3,
      'offset': 0,
      'nextOffset': 3,
      'dataBase64': base64Encode(<int>[1, 2, 3]),
    }..addAll(change);
    expect(AgentChatAttachmentChunk.fromJson(piece({})).isLast, isTrue);
    for (final change in <Map<String, Object?>>[
      {'mimeType': 'application/pdf'},
      {'sizeBytes': agentChatAttachmentReadMaxBytes + 1},
      {'nextOffset': 2},
      {'offset': -1},
      {'dataBase64': '%%'},
    ]) {
      expect(
        () => AgentChatAttachmentChunk.fromJson(piece(change)),
        throwsFormatException,
        reason: change.keys.single,
      );
    }
  });

  test('the cache keeps recent bytes within its bound', () async {
    final cache = AgentChatAttachmentCache(maxBytes: 250);
    final small = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      ...List<int>.filled(96, 0),
    ]);
    var fetches = 0;
    Future<AgentChatAttachmentBytes> fetch(String id) {
      fetches += 1;
      return _load(small, id);
    }

    await cache.load('a', () => fetch('a'));
    await cache.load('b', () => fetch('b'));
    expect(cache.sizeBytes, 200);
    await cache.load('a', () => fetch('a'));
    expect(fetches, 2);
    await cache.load('c', () => fetch('c'));
    // `b` was the least recently used.
    expect(cache.peek('b'), isNull);
    expect(cache.peek('a'), isNotNull);
    expect(cache.peek('c'), isNotNull);
    expect(cache.sizeBytes, 200);
    final shared = <Future<AgentChatAttachmentBytes>>[
      cache.load('d', () => fetch('d')),
      cache.load('d', () => fetch('d')),
    ];
    await Future.wait(shared);
    expect(fetches, 4);
    await expectLater(
      cache.load('e', () => Future.error(StateError('offline'))),
      throwsStateError,
    );
    expect(cache.peek('e'), isNull);
  });

  test('a preview is null without the capability or for video', () async {
    final attachment = AgentChatAttachment.fromJson(<String, Object?>{
      'type': 'localImage',
      'name': 'photo.png',
      'attachmentId': 'a-1',
    });
    expect(agentChatAttachmentHostReadable(attachment), isTrue);
    expect(
      agentChatAttachmentHostReadable(
        AgentChatAttachment.fromJson(<String, Object?>{
          'type': 'file',
          'name': 'clip.mp4',
          'attachmentId': 'a-2',
        }),
      ),
      isFalse,
    );
    expect(
      agentChatAttachmentHostReadable(
        AgentChatAttachment.fromJson(<String, Object?>{
          'type': 'localImage',
          'name': 'photo.png',
        }),
      ),
      isFalse,
    );
    final unsupported = _AttachmentTransport(_png, supported: false);
    expect(
      await fetchAgentChatAttachmentPreview(
        RuntimeAgentChatLifecycleRepository(unsupported),
        _chat,
        attachmentId: 'a-1',
        cache: AgentChatAttachmentCache(),
        key: 'a-1',
      ),
      isNull,
    );
    expect(unsupported.requests, isEmpty);
    expect(
      await fetchAgentChatAttachmentPreview(
        RuntimeAgentChatLifecycleRepository(
          _AttachmentTransport(_png, mimeType: 'video/mp4'),
        ),
        _chat,
        attachmentId: 'a-1',
        cache: AgentChatAttachmentCache(),
        key: 'a-1',
      ),
      isNull,
    );
    final cache = AgentChatAttachmentCache();
    final preview = await fetchAgentChatAttachmentPreview(
      RuntimeAgentChatLifecycleRepository(_AttachmentTransport(_png)),
      _chat,
      attachmentId: 'a-1',
      cache: cache,
      key: 'a-1',
    );
    expect(preview?.bytes, _png);
    expect(cache.peek('a-1'), same(preview));
  });
}
