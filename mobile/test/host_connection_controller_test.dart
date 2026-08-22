import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('A dropped socket reconnects and authenticates automatically', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      await server.close(force: true);
    });
    var helloCount = 0;
    final reconnected = Completer<void>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        if (message['type'] == 'mobile.hello') {
          helloCount += 1;
          if (helloCount == 2 && !reconnected.isCompleted) {
            reconnected.complete();
          }
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
    var sawLostConnection = false;
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, next) {
        if (next.error is RuntimeConnectionLost) {
          sawLostConnection = true;
        }
      },
    );
    addTearDown(connection.close);
    await container.read(hostConnectionControllerProvider('runtime-1').future);

    await sockets.single.close();
    await reconnected.future.timeout(const Duration(seconds: 5));
    await _waitUntil(() {
      final state = container.read(
        hostConnectionControllerProvider('runtime-1'),
      );
      return state.hasValue && !state.hasError;
    });

    expect(sawLostConnection, isTrue);
    expect(helloCount, 2);
    final state = container.read(hostConnectionControllerProvider('runtime-1'));
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
  });

  test(
    'A dropped socket waits in background and reconnects on resume',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      var helloCount = 0;
      final reconnected = Completer<void>();
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, Object?>;
          if (message['type'] == 'mobile.hello') {
            helloCount += 1;
          }
          socket.add(
            jsonEncode(<String, Object?>{
              'id': message['id'],
              'ok': true,
              'payload': <String, Object?>{},
            }),
          );
          if (message['type'] == 'status.get' &&
              helloCount == 2 &&
              !reconnected.isCompleted) {
            reconnected.complete();
          }
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
      final lifecycle = _TestAppLifecycleController();
      final container = ProviderContainer(
        overrides: [
          hostRepositoryProvider.overrideWithValue(repository),
          cloudAccountRepositoryProvider.overrideWithValue(
            _InstallationRepository(),
          ),
          appLifecycleControllerProvider.overrideWith(() => lifecycle),
        ],
      );
      addTearDown(container.dispose);
      final connection = container.listen(
        hostConnectionControllerProvider('runtime-1'),
        (_, _) {},
      );
      addTearDown(connection.close);
      await container.read(
        hostConnectionControllerProvider('runtime-1').future,
      );

      await sockets.single.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(helloCount, 1);
      expect(
        container.read(hostConnectionControllerProvider('runtime-1')).hasError,
        isTrue,
      );

      lifecycle.setLifecycleState(AppLifecycleState.resumed);
      await reconnected.future.timeout(const Duration(seconds: 5));
      await _waitUntil(
        () => container
            .read(hostConnectionControllerProvider('runtime-1'))
            .hasValue,
      );
      expect(helloCount, 2);
    },
  );

  test('A failed foreground probe replaces a half-open client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    var helloCount = 0;
    final reconnected = Completer<void>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) async {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        if (message['type'] == 'mobile.hello') {
          helloCount += 1;
        }
        if (message['type'] == 'mobile.status.get') {
          await socket.close();
          return;
        }
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{},
          }),
        );
        if (message['type'] == 'status.get' &&
            helloCount == 2 &&
            !reconnected.isCompleted) {
          reconnected.complete();
        }
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
    final lifecycle = _TestAppLifecycleController(AppLifecycleState.resumed);
    final container = ProviderContainer(
      overrides: [
        hostRepositoryProvider.overrideWithValue(repository),
        cloudAccountRepositoryProvider.overrideWithValue(
          _InstallationRepository(),
        ),
        appLifecycleControllerProvider.overrideWith(() => lifecycle),
      ],
    );
    addTearDown(container.dispose);
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, _) {},
    );
    addTearDown(connection.close);
    await container.read(hostConnectionControllerProvider('runtime-1').future);

    lifecycle.setLifecycleState(AppLifecycleState.inactive);
    lifecycle.setLifecycleState(AppLifecycleState.resumed);
    await reconnected.future.timeout(const Duration(seconds: 5));
    await _waitUntil(
      () => container
          .read(hostConnectionControllerProvider('runtime-1'))
          .hasValue,
    );
    expect(helloCount, 2);
  });

  test('An unavailable host becomes retryable state and reconnects', () async {
    final reservation = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final address = reservation.address;
    final port = reservation.port;
    await reservation.close(force: true);

    HttpServer? recoveryServer;
    StreamSubscription<HttpRequest>? serverSubscription;
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await serverSubscription?.cancel();
      await recoveryServer?.close(force: true);
    });

    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime-1',
        displayName: 'Alera Host',
        endpoint: 'ws://${address.address}:$port',
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
    final observedErrors = <Object>[];
    final unreachable = Completer<Object>();
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, next) {
        final error = next.error;
        if (error != null) {
          observedErrors.add(error);
          if (!unreachable.isCompleted) {
            unreachable.complete(error);
          }
        }
      },
    );
    addTearDown(connection.close);

    expect(
      await unreachable.future.timeout(const Duration(seconds: 5)),
      isA<HostUnreachableException>(),
    );

    recoveryServer = await HttpServer.bind(address, port);
    serverSubscription = recoveryServer.listen((request) async {
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

    await _waitUntil(
      () => container
          .read(hostConnectionControllerProvider('runtime-1'))
          .hasValue,
    );

    expect(observedErrors, contains(isA<HostUnreachableException>()));
    expect(
      container.read(hostConnectionControllerProvider('runtime-1')).hasError,
      isFalse,
    );
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

class _TestAppLifecycleController extends AppLifecycleController {
  _TestAppLifecycleController([this.initialState = AppLifecycleState.paused]);

  final AppLifecycleState initialState;

  @override
  AppLifecycleState build() => initialState;

  void setLifecycleState(AppLifecycleState next) {
    state = next;
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
