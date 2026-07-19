import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  test('Connects and authenticates against the paired endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    final helloPayload = Completer<Map<String, Object?>>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        if (message['type'] == 'mobile.hello' && !helloPayload.isCompleted) {
          helloPayload.complete(message['payload']! as Map<String, Object?>);
        }
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{},
          }),
        );
      });
    });
    addTearDown(() async {
      await subscription.cancel();
    });

    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime-1',
        displayName: 'Alera Host',
        endpoint: 'ws://${server.address.address}:${server.port}',
        runtimeId: 'runtime-1',
        deviceId: 'device-1',
        pairedAt: DateTime.now().toUtc(),
      ),
      'token-1',
    );
    final container = ProviderContainer(
      overrides: [hostRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, _) {},
    );
    addTearDown(connection.close);

    await container.read(hostConnectionControllerProvider('runtime-1').future);
    final payload = await helloPayload.future.timeout(
      const Duration(seconds: 5),
    );
    expect(payload['deviceId'], 'device-1');
    expect(payload['deviceToken'], 'token-1');
  });

  test('Fails when the host is not paired', () async {
    final container = ProviderContainer(
      overrides: [
        hostRepositoryProvider.overrideWithValue(MemoryHostRepository()),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(hostConnectionControllerProvider('missing').future),
      throwsA(isA<StateError>()),
    );
  });
}
