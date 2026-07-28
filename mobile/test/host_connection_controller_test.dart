import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
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
      overrides: [
        hostRepositoryProvider.overrideWithValue(repository),
        cloudAccountRepositoryProvider.overrideWithValue(
          _InstallationRepository(),
        ),
      ],
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
    expect(payload['cloudDeviceId'], 'cloud-installation-1');
  });

  test('A dropped socket surfaces as a lost connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      await server.close(force: true);
    });
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{},
          }),
        );
      });
    });
    addTearDown(subscription.cancel);

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
      overrides: [
        hostRepositoryProvider.overrideWithValue(repository),
        cloudAccountRepositoryProvider.overrideWithValue(
          _InstallationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final lost = Completer<Object?>();
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, next) {
        if (next is AsyncError && !lost.isCompleted) {
          lost.complete(next.error);
        }
      },
    );
    addTearDown(connection.close);
    await container.read(hostConnectionControllerProvider('runtime-1').future);

    for (final socket in sockets) {
      await socket.close();
    }

    // A half-open socket raises nothing on its own, so the provider has to say
    // so or every screen keeps showing a live connection. Riverpod keeps the
    // previous value alongside the error, which is why callers check hasError.
    final error = await lost.future.timeout(const Duration(seconds: 5));
    expect(error, isA<RuntimeConnectionLost>());
    final state = container.read(hostConnectionControllerProvider('runtime-1'));
    expect(state.hasError, isTrue);
    expect(state.error, isA<RuntimeConnectionLost>());
  });

  test('Fails when the host is not paired', () async {
    final container = ProviderContainer(
      overrides: [
        hostRepositoryProvider.overrideWithValue(MemoryHostRepository()),
        cloudAccountRepositoryProvider.overrideWithValue(
          _InstallationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(hostConnectionControllerProvider('missing').future),
      throwsA(isA<StateError>()),
    );
  });
}

class _InstallationRepository implements CloudAccountRepository {
  @override
  Future<String> getOrCreateInstallationId() async => 'cloud-installation-1';

  @override
  Future<List<CloudAccountSession>> loadSessions() async =>
      const <CloudAccountSession>[];

  @override
  Future<void> removeSession(String accountId) async {}

  @override
  Future<void> saveSession(CloudAccountSession session) async {}
}
