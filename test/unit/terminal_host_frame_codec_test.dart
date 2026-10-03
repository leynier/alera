import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalHostFrameReader', () {
    test('reads newline JSON before the upgrade', () {
      final reader = TerminalHostFrameReader();

      final frames = reader.add(utf8.encode('{"a":1}\n{"b":2}\n'));

      expect(frames, hasLength(2));
      expect((frames[0] as TerminalHostJsonFrame).json, '{"a":1}');
      expect((frames[1] as TerminalHostJsonFrame).json, '{"b":2}');
    });

    test('a line split across chunks is reassembled', () {
      final reader = TerminalHostFrameReader();

      expect(reader.add(utf8.encode('{"a":')), isEmpty);
      final frames = reader.add(utf8.encode('1}\n'));

      expect((frames.single as TerminalHostJsonFrame).json, '{"a":1}');
    });

    test('switches to frames only after the upgrade', () {
      // The handshake response is a line; everything after it is framed. This
      // ordering is what the in-band upgrade on the host guarantees.
      final reader = TerminalHostFrameReader();
      final lines = reader.add(utf8.encode('{"ok":true}\n'));
      expect((lines.single as TerminalHostJsonFrame).json, '{"ok":true}');

      reader.upgradeToBinary();
      final frames = reader.add(
        encodeTerminalHostOutputFrame('session-1', <int>[1, 2, 3]),
      );

      final output = frames.single as TerminalHostOutputFrame;
      expect(output.sessionId, 'session-1');
      expect(output.data, <int>[1, 2, 3]);
    });

    test('an output frame carries raw bytes, including invalid UTF-8', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();
      final data = <int>[0x1b, 0x5b, 0x30, 0x6d, 0xff, 0x00];

      final frames = reader.add(
        encodeTerminalHostOutputFrame('session-1', data),
      );

      expect((frames.single as TerminalHostOutputFrame).data, data);
    });

    test('a frame split across chunks is reassembled', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();
      final bytes = encodeTerminalHostOutputFrame('session-1', <int>[7, 8, 9]);

      expect(reader.add(bytes.sublist(0, 3)), isEmpty);
      expect(reader.add(bytes.sublist(3, 8)), isEmpty);
      final frames = reader.add(bytes.sublist(8));

      expect((frames.single as TerminalHostOutputFrame).data, <int>[7, 8, 9]);
    });

    test('several frames in one chunk all come out', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();
      final bytes = <int>[
        ...encodeTerminalHostOutputFrame('a', <int>[1]),
        ...encodeTerminalHostJsonFrame('{"event":"exit"}'),
        ...encodeTerminalHostOutputFrame('b', <int>[2]),
      ];

      final frames = reader.add(bytes);

      expect(frames, hasLength(3));
      expect((frames[0] as TerminalHostOutputFrame).sessionId, 'a');
      expect((frames[1] as TerminalHostJsonFrame).json, '{"event":"exit"}');
      expect((frames[2] as TerminalHostOutputFrame).sessionId, 'b');
    });

    test('empty payloads round-trip', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();

      final frames = reader.add(encodeTerminalHostOutputFrame('', <int>[]));

      final output = frames.single as TerminalHostOutputFrame;
      expect(output.sessionId, isEmpty);
      expect(output.data, isEmpty);
    });

    test('any chunking of a mixed stream yields the same frames', () {
      final stream = <int>[
        ...utf8.encode('{"hello":true}\n'),
        ...utf8.encode('binaryFramesEnabled\n'),
      ];
      final expected = <String>['{"hello":true}', 'binaryFramesEnabled'];
      for (var index = 0; index < 400; index += 1) {
        final data = List<int>.generate(
          index % 37,
          (byte) => (byte + index) & 0xff,
        );
        if (index.isEven) {
          stream.addAll(encodeTerminalHostOutputFrame('s$index', data));
          expected.add('s$index:${data.join(',')}');
        } else {
          stream.addAll(encodeTerminalHostJsonFrame('{"i":$index}'));
          expected.add('{"i":$index}');
        }
      }
      final random = Random(7);
      for (var round = 0; round < 20; round += 1) {
        final reader = TerminalHostFrameReader();
        final frames = <String>[];
        var offset = 0;
        while (offset < stream.length) {
          final size = 1 + random.nextInt(round.isEven ? 7 : 4096);
          final end = min(offset + size, stream.length);
          for (final frame in reader.add(stream.sublist(offset, end))) {
            frames.add(switch (frame) {
              TerminalHostJsonFrame(:final json) => json,
              TerminalHostOutputFrame(:final sessionId, :final data) =>
                '$sessionId:${data.join(',')}',
            });
          }
          offset = end;
        }
        expect(frames, expected, reason: 'round $round');
      }
    });

    test('output data stays intact after the buffer is reused', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();
      final first = reader.add(
        encodeTerminalHostOutputFrame('a', List<int>.filled(1024, 1)),
      );
      reader.add(
        encodeTerminalHostOutputFrame('b', List<int>.filled(1024 * 1024, 2)),
      );
      reader.add(encodeTerminalHostOutputFrame('c', List<int>.filled(8, 3)));

      expect(
        (first.single as TerminalHostOutputFrame).data.every(
          (byte) => byte == 1,
        ),
        isTrue,
      );
    });

    test('a frame larger than the initial buffer is reassembled', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();
      final data = List<int>.generate(3 * 1024 * 1024, (index) => index & 0xff);
      final bytes = encodeTerminalHostOutputFrame('big', data);
      final frames = <TerminalHostFrame>[];
      for (var offset = 0; offset < bytes.length; offset += 65536) {
        frames.addAll(
          reader.add(bytes.sublist(offset, min(offset + 65536, bytes.length))),
        );
      }

      expect((frames.single as TerminalHostOutputFrame).data, data);
    });

    test('a multi-byte session id survives the byte-counted prefix', () {
      final reader = TerminalHostFrameReader()..upgradeToBinary();

      final frames = reader.add(
        encodeTerminalHostOutputFrame('sesión', <int>[1]),
      );

      expect((frames.single as TerminalHostOutputFrame).sessionId, 'sesión');
    });
  });

  group('cross-implementation contract', () {
    // Hardcoded bytes both sides must agree on. Without this the two codecs
    // can drift apart while each stays self-consistent.
    test('a JSON frame has the exact expected header', () {
      final bytes = encodeTerminalHostJsonFrame('{}');

      expect(bytes, <int>[1, 0, 0, 0, 2, 0x7b, 0x7d]);
    });

    test('an output frame has the exact expected layout', () {
      final bytes = encodeTerminalHostOutputFrame('ab', <int>[0xff]);

      expect(bytes, <int>[
        2, // kind
        0, 0, 0, 5, // payload length: 2 id-length bytes + 2 id + 1 data
        0, 2, // session id length
        0x61, 0x62, // "ab"
        0xff, // raw data
      ]);
    });
  });

  test('encodeTerminalHostOutputFrame returns a typed byte list', () {
    expect(
      encodeTerminalHostOutputFrame('a', <int>[1]),
      isA<Uint8List>(),
      reason: 'the socket writer needs bytes, not a boxed list',
    );
  });
}
