import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'feature detects prompt image uploads and sends ordered chunks',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final requests = <Map<String, Object?>>[];
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, Object?>;
          requests.add(message);
          final type = message['type'];
          final payload = switch (type) {
            'mobile.hello' => <String, Object?>{
              'runtimeCapabilities': <String>[
                mobilePromptImageUploadCapability,
              ],
            },
            'mobile.promptImage.start' => <String, Object?>{
              'uploadId': '00000000-0000-4000-8000-000000000001',
              'chunkBytes': 256 * 1024,
            },
            'mobile.promptImage.chunk' => <String, Object?>{
              'nextOffset':
                  ((message['payload']! as Map<String, Object?>)['offset']!
                      as int) +
                  base64Decode(
                    (message['payload']! as Map<String, Object?>)['dataBase64']!
                        as String,
                  ).length,
            },
            'mobile.promptImage.complete' => <String, Object?>{
              'path': '/runtime/prompt-images/00000000-0000-4000-8000-000000000001.png',
            },
            _ => <String, Object?>{},
          };
          socket.add(
            jsonEncode(<String, Object?>{
              'id': message['id'],
              'ok': true,
              'payload': payload,
            }),
          );
        });
      });
      addTearDown(subscription.cancel);

      final client = await MobileRuntimeClient.connect(
        'ws://${server.address.address}:${server.port}',
      );
      addTearDown(client.dispose);
      expect(client.supportsPromptImageUpload, isFalse);
      await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
      expect(client.supportsPromptImageUpload, isTrue);

      final bytes = List<int>.generate(300000, (index) => index & 0xff);
      final result = await client.uploadPromptImage(
        format: 'png',
        sizeBytes: bytes.length,
        openRead: () => Stream<List<int>>.value(bytes),
      );

      expect(result.hostPath, endsWith('.png'));
      expect(requests.map((request) => request['type']), <Object?>[
        'mobile.hello',
        'status.get',
        'mobile.promptImage.start',
        'mobile.promptImage.chunk',
        'mobile.promptImage.chunk',
        'mobile.promptImage.complete',
      ]);
      final chunks = requests
          .where((request) => request['type'] == 'mobile.promptImage.chunk')
          .map((request) => request['payload']! as Map<String, Object?>)
          .toList();
      expect(chunks.map((chunk) => (chunk['offset']! as int)), <int>[
        0,
        256 * 1024,
      ]);
      expect(
        chunks.map(
          (chunk) => base64Decode(chunk['dataBase64']! as String).length,
        ),
        <int>[256 * 1024, 300000 - 256 * 1024],
      );
    },
  );

  test('cancels a prompt image upload after a later chunk fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final requestTypes = <String>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        final type = message['type']! as String;
        requestTypes.add(type);
        final payload = message['payload']! as Map<String, Object?>;
        final chunkNumber = requestTypes
            .where((value) => value == 'mobile.promptImage.chunk')
            .length;
        final response = type == 'mobile.hello'
            ? <String, Object?>{
                'runtimeCapabilities': <String>[
                  mobilePromptImageUploadCapability,
                ],
              }
            : type == 'mobile.promptImage.start'
            ? <String, Object?>{
                'uploadId': '00000000-0000-4000-8000-000000000002',
              }
            : type == 'mobile.promptImage.chunk' && chunkNumber == 2
            ? <String, Object?>{}
            : type == 'mobile.promptImage.chunk'
            ? <String, Object?>{
                'nextOffset':
                    (payload['offset']! as int) +
                    base64Decode(payload['dataBase64']! as String).length,
              }
            : <String, Object?>{};
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': !(type == 'mobile.promptImage.chunk' && chunkNumber == 2),
            if (type == 'mobile.promptImage.chunk' && chunkNumber == 2)
              'error': 'chunk failed'
            else
              'payload': response,
          }),
        );
      });
    });
    addTearDown(subscription.cancel);

    final client = await MobileRuntimeClient.connect(
      'ws://${server.address.address}:${server.port}',
    );
    addTearDown(client.dispose);
    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

    final bytes = List<int>.filled(300000, 7);
    await expectLater(
      client.uploadPromptImage(
        format: 'jpeg',
        sizeBytes: bytes.length,
        openRead: () => Stream<List<int>>.value(bytes),
      ),
      throwsA(isA<StateError>()),
    );
    expect(requestTypes.last, 'mobile.promptImage.cancel');
  });
}
