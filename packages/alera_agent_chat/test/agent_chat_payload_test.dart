import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

const _chat = AgentChatRef(chatId: 'chat', workspaceId: 'workspace');

Map<String, Object?> _page(
  List<(int, String)> chunks, {
  required int count,
  int? next,
  String revision = 'payload-1',
}) => <String, Object?>{
  'chunks': <Map<String, Object?>>[
    for (final (index, text) in chunks)
      <String, Object?>{'index': index, 'text': text},
  ],
  'segmentCount': count,
  'format': 'json',
  'revision': revision,
  'nextIndex': ?next,
};

final class _Transport implements AgentChatTransport {
  bool capable = true;
  final requests = <(String, Map<String, Object?>)>[];
  Map<String, Object?> Function(Map<String, Object?>)? respond;

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async => capable;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    return respond!(payload);
  }
}

void main() {
  test(
    'payload page is optional and scoped without a mutation receipt',
    () async {
      final transport = _Transport()
        ..respond = (_) => _page(<(int, String)>[(2, 'tail')], count: 3);
      final repository = RuntimeAgentChatRepository(transport);
      expect(repository, isA<AgentChatRepository>());
      expect(repository, isA<AgentChatPayloadRepository>());
      final page = await repository.payload(
        _chat,
        itemId: 'head',
        index: 2,
        limit: 1,
      );
      expect(page.chunks.single.index, 2);
      expect(page.chunks.single.text, 'tail');
      expect(page.nextIndex, isNull);
      expect(page.format, 'json');
      expect(transport.requests.single.$1, AgentChatWire.payload);
      expect(transport.requests.single.$2, <String, Object?>{
        'chatId': 'chat',
        'workspaceId': 'workspace',
        'itemId': 'head',
        'index': 2,
        'limit': 1,
      });
      expect(() => page.chunks.clear(), throwsUnsupportedError);
    },
  );

  test(
    'explicit load joins exact JSON without decoding or normalizing it',
    () async {
      const parts = <String>[
        ' {"nested":"🧪',
        r'\n\"value',
        '", "spaced" : [1, true]}\n',
      ];
      final transport = _Transport()
        ..respond = (request) {
          final index = request['index']! as int;
          return _page(
            <(int, String)>[(index, parts[index])],
            count: parts.length,
            next: index + 1 < parts.length ? index + 1 : null,
          );
        };
      final repository = RuntimeAgentChatRepository(transport);
      expect(transport.requests, isEmpty);
      final loaded = await repository.loadPayloadJson(
        _chat,
        itemId: 'head',
        limit: 1,
      );
      expect(loaded, parts.join());
      expect(transport.requests.map((request) => request.$2['index']), <int>[
        0,
        1,
        2,
      ]);
      expect(jsonDecode(loaded), isA<Map>());
    },
  );

  test('payload request fails closed on unsupported runtimes', () async {
    final transport = _Transport()..capable = false;
    await expectLater(
      RuntimeAgentChatRepository(transport).payload(_chat, itemId: 'head'),
      throwsA(isA<AgentChatUpdateRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('invalid request cursors never reach the transport', () async {
    final transport = _Transport();
    final repository = RuntimeAgentChatRepository(transport);
    for (final (id, index, limit) in <(String, int, int?)>[
      ('', 0, null),
      ('head', -1, null),
      ('head', 0, 0),
    ]) {
      await expectLater(
        repository.payload(_chat, itemId: id, index: index, limit: limit),
        throwsFormatException,
      );
    }
    expect(transport.requests, isEmpty);
  });

  test(
    'page parser rejects missing shapes, wrong indices and oversized UTF-8',
    () {
      final malformed = <Object?>[
        null,
        <String, Object?>{
          'format': 'json',
          'segmentCount': 1,
          'chunks': <Object?>[],
        },
        <String, Object?>{
          ..._page(<(int, String)>[(0, 'x')], count: 1),
          'segmentCount': '1',
        },
        <String, Object?>{
          ..._page(<(int, String)>[(0, 'x')], count: 1),
          'format': 'text',
        },
        _page(<(int, String)>[(-1, 'x')], count: 1),
        _page(<(int, String)>[(1, 'x')], count: 1),
        <String, Object?>{
          ..._page(<(int, String)>[(0, 'x')], count: 1),
          'nextIndex': '1',
        },
        _page(<(int, String)>[(0, '🧪' * 70_000)], count: 1),
      ];
      for (final json in malformed) {
        expect(
          () => AgentChatPayloadPage.fromJson(json),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'full load rejects gaps, duplicate indices and invalid next cursors',
    () async {
      final malformed = <Map<String, Object?>>[
        _page(<(int, String)>[(1, 'x')], count: 2),
        _page(<(int, String)>[(0, 'x'), (0, 'x')], count: 2),
        _page(<(int, String)>[(0, 'x')], count: 2),
        _page(<(int, String)>[(0, 'x')], count: 2, next: 0),
        _page(<(int, String)>[(0, 'x')], count: 1, next: 1),
      ];
      for (final page in malformed) {
        final transport = _Transport()..respond = (_) => page;
        await expectLater(
          RuntimeAgentChatRepository(transport)
              .loadPayloadJson(_chat, itemId: 'head'),
          throwsFormatException,
        );
        expect(transport.requests, hasLength(1));
      }
    },
  );

  test('full load rejects a changed payload segment count', () async {
    final transport = _Transport()
      ..respond = (request) => request['index'] == 0
          ? _page(<(int, String)>[(0, 'start')], count: 2, next: 1)
          : _page(<(int, String)>[(1, 'changed')], count: 3, next: 2);
    await expectLater(
      RuntimeAgentChatRepository(transport)
          .loadPayloadJson(_chat, itemId: 'head'),
      throwsFormatException,
    );
    expect(transport.requests, hasLength(2));
  });

  test('full load rejects changed data with the same segment count', () async {
    final transport = _Transport()
      ..respond = (request) => request['index'] == 0
          ? _page(<(int, String)>[(0, 'start')], count: 2, next: 1)
          : _page(
              <(int, String)>[(1, 'changed')],
              count: 2,
              revision: 'payload-2',
            );
    await expectLater(
      RuntimeAgentChatRepository(transport)
          .loadPayloadJson(_chat, itemId: 'head'),
      throwsFormatException,
    );
    expect(transport.requests, hasLength(2));
  });
}
