import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  tearDown(CrashReporting.resetForTesting);

  test('Creates Account Enrollment Through A Capable Paired Host', () async {
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
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': switch (type) {
              'status.get' => <String, Object?>{
                'runtimeHostVersion': '1.7.0',
                'runtimeHostCommit': 'abc1234',
                'protocolVersion': 4,
              },
              'mobile.hello' => <String, Object?>{
                'runtimeCapabilities': <String>[
                  mobileCloudEnrollmentCapability,
                ],
              },
              'mobile.cloudEnrollment.create' => <String, Object?>{
                'code': 'enrollment-code',
              },
              'mobile.cloudSubscriptions.refresh' => <String, Object?>{
                'activeSubscriptions': 2,
              },
              _ => <String, Object?>{},
            },
          }),
        );
      });
    });
    addTearDown(subscription.cancel);

    final client = await MobileRuntimeClient.connect(
      'ws://${server.address.address}:${server.port}',
    );
    addTearDown(client.dispose);
    await client.authenticate(
      deviceId: 'device-1',
      deviceToken: 'token-1',
      cloudDeviceId: 'cloud-installation-1',
    );

    CrashReporting.setEnabled(true);
    final crash = CrashReporting.filterEvent(SentryEvent());
    expect(crash!.tags, containsPair('runtime_version', '1.7.0'));
    expect(crash.tags, containsPair('runtime_build', 'abc1234'));
    expect(crash.tags, containsPair('runtime_protocol', '4'));

    expect(client.supportsCloudEnrollment, isTrue);
    expect(await client.createCloudEnrollment(), 'enrollment-code');
    expect(
      (requests.first['payload']! as Map<String, Object?>)['cloudDeviceId'],
      'cloud-installation-1',
    );
    expect(requests.last['type'], 'mobile.cloudEnrollment.create');
    expect(await client.refreshCloudSubscriptions(), 2);
    expect(requests.last['type'], 'mobile.cloudSubscriptions.refresh');
  });

  test(
    'Feature detects Claude TUI quota capability during authentication',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
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
          socket.add(
            jsonEncode(<String, Object?>{
              'id': message['id'],
              'ok': true,
              'payload': <String, Object?>{
                'runtimeCapabilities': <String>[
                  mobileAgentQuotaClaudeTuiCapability,
                ],
              },
            }),
          );
        });
      });
      addTearDown(subscription.cancel);

      final client = await MobileRuntimeClient.connect(
        'ws://${server.address.address}:${server.port}',
      );
      addTearDown(client.dispose);
      expect(client.supportsAgentQuotaClaudeTui, isFalse);

      await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

      expect(client.supportsAgentQuotaClaudeTui, isTrue);
    },
  );

  test('Claude TUI quota fetch uses the dedicated runtime request', () async {
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
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{
              'snapshot': <String, Object?>{
                'provider': 'claude',
                'accountId': 'partsbase',
                'displayName': 'Partsbase',
                'status': 'ok',
                'updatedAt': DateTime.utc(2026).millisecondsSinceEpoch,
                'windows': <Object?>[],
                'buckets': <Object?>[],
              },
            },
          }),
        );
      });
    });
    addTearDown(subscription.cancel);

    final client = await MobileRuntimeClient.connect(
      'ws://${server.address.address}:${server.port}',
    );
    addTearDown(client.dispose);

    final snapshot = await client.fetchClaudeQuotaViaTui(
      accountId: 'partsbase',
      displayName: 'Partsbase',
    );

    expect(snapshot.accountId, 'partsbase');
    expect(snapshot.status, 'ok');
    expect(requests, hasLength(1));
    expect(requests.single['type'], 'agentQuota.fetchClaudeTui');
    expect(requests.single['payload'], <String, Object?>{
      'accountId': 'partsbase',
      'displayName': 'Partsbase',
    });
  });

  test(
    'Feature detects synchronized terminal titles during authentication',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
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
          socket.add(
            jsonEncode(<String, Object?>{
              'id': message['id'],
              'ok': true,
              'payload': <String, Object?>{
                'runtimeCapabilities': <String>[mobileTerminalTitlesCapability],
              },
            }),
          );
        });
      });
      addTearDown(subscription.cancel);

      final client = await MobileRuntimeClient.connect(
        'ws://${server.address.address}:${server.port}',
      );
      addTearDown(client.dispose);
      expect(client.supportsTerminalTitles, isFalse);

      await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

      expect(client.supportsTerminalTitles, isTrue);
    },
  );

  test('Pairing requests omit device name by default', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    final receivedPayload = Completer<Map<String, Object?>>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        receivedPayload.complete(message['payload']! as Map<String, Object?>);
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{
              'deviceId': 'device-1',
              'displayName': 'Expected Phone',
              'runtimeId': 'runtime-1',
              'deviceToken': 'token-1',
            },
          }),
        );
      });
    });
    addTearDown(() async {
      await subscription.cancel();
    });

    final credentials = await MobileRuntimeClient.pairDevice(
      PairingOffer(
        version: aleraMobileProtocolVersion,
        pairingId: 'pairing-1',
        endpoint: 'ws://${server.address.address}:${server.port}',
        runtimeId: 'runtime-1',
        hostName: 'Alera Host',
        pairingSecret: 'secret-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
    );

    final payload = await receivedPayload.future.timeout(
      const Duration(seconds: 5),
    );
    expect(payload, isNot(contains('deviceName')));
    expect(credentials.displayName, 'Expected Phone');
  });

  test('Requests fail immediately after the runtime socket closes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final socketClosed = Completer<void>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
      await socket.done;
      if (!socketClosed.isCompleted) {
        socketClosed.complete();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
    });

    final client = await MobileRuntimeClient.connect(
      'ws://${server.address.address}:${server.port}',
    );
    addTearDown(client.dispose);

    await socketClosed.future.timeout(const Duration(seconds: 5));
    await pumpEventQueue(times: 5);

    await expectLater(
      client
          .request('mobile.status.get')
          .timeout(const Duration(milliseconds: 250)),
      throwsA(isA<RuntimeConnectionLost>()),
    );
  });

  test('Timed-out requests are removed from pending requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    final accepted = Completer<void>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      if (!accepted.isCompleted) {
        accepted.complete();
      }
      await socket.done;
    });
    addTearDown(() async {
      await subscription.cancel();
    });

    final channel = WebSocketChannel.connect(
      Uri.parse('ws://${server.address.address}:${server.port}'),
    );
    await channel.ready.timeout(const Duration(seconds: 5));
    final client = MobileRuntimeClient.forTesting(
      channel,
      requestTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(client.dispose);
    await accepted.future.timeout(const Duration(seconds: 5));

    await expectLater(
      client.request('mobile.status.get'),
      throwsA(isA<TimeoutException>()),
    );

    expect(client.debugPendingRequestCount, 0);
  });

  test(
    'Project management requests use high-level runtime contracts',
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
            'project.register' => <String, Object?>{
              'project': <String, Object?>{
                'id': 'project-1',
                'name': 'Alera',
                'repoPath': '/srv/alera',
                'kind': 'gitRepository',
              },
              'mainWorkspace': <String, Object?>{
                'id': 'workspace-1',
                'instanceId': 'instance-1',
                'hostId': 'local',
                'projectId': 'project-1',
                'name': 'Alera',
                'path': '/srv/alera',
                'kind': 'main',
                'status': 'active',
              },
              'created': true,
            },
            'project.clone.start' => <String, Object?>{
              'id': 'job-1',
              'source': 'https://example.com/alera.git',
              'destinationPath': '/srv/alera',
              'status': 'queued',
              'phase': 'cloning',
              'updatedAt': DateTime.utc(2026).toIso8601String(),
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

      final registration = await client.registerProject(
        path: '/srv/alera',
        name: 'Alera',
      );
      final job = await client.startProjectClone(
        url: 'https://example.com/alera.git',
        parentPath: '/srv',
        directoryName: 'alera',
      );

      expect(registration.mainWorkspace.id, 'workspace-1');
      expect(registration.created, isTrue);
      expect(job.id, 'job-1');
      expect(requests.map((request) => request['type']), <Object?>[
        'project.register',
        'project.clone.start',
      ]);
      expect(
        (requests.last['payload']! as Map<String, Object?>)['parentPath'],
        '/srv',
      );
    },
  );
}
