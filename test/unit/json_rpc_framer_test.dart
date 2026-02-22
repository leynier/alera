import 'dart:convert';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_framer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonRpcFramer', () {
    test('parses Content-Length framed messages across chunks', () {
      final framer = JsonRpcFramer();
      final payload = jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, dynamic>{'ok': true},
      });

      final frame =
          'Content-Length: ${utf8.encode(payload).length}\r\n\r\n$payload';
      final partA = frame.substring(0, 20);
      final partB = frame.substring(20);

      expect(framer.addChunk(utf8.encode(partA)), isEmpty);

      final messages = framer.addChunk(utf8.encode(partB));
      expect(messages, hasLength(1));
      expect(messages.first['id'], 1);
      expect((messages.first['result'] as Map<String, dynamic>)['ok'], true);
    });

    test('parses json line payloads', () {
      final framer = JsonRpcFramer();
      final messages = framer.addChunk(
        utf8.encode('{"jsonrpc":"2.0","method":"event"}\n'),
      );

      expect(messages, hasLength(1));
      expect(messages.first['method'], 'event');
    });

    test('throws for non-object json payload', () {
      final framer = JsonRpcFramer();

      expect(
        () => framer.addChunk(utf8.encode('[1,2,3]\n')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
