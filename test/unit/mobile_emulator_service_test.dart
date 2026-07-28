import 'dart:async';

import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_lease_coordinator.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_surface_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileEmulatorService', () {
    test('parses virtual devices and sends the selected platform', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{
        'ok': true,
        'items': <Object?>[
          <String, Object?>{
            'id': 'pixel-9',
            'platform': 'android',
            'name': 'Pixel 9',
            'state': 'stopped',
            'available': true,
          },
        ],
      });
      final service = MobileEmulatorService(client);

      final devices = await service.devices(
        platform: MobileEmulatorPlatform.android,
      );

      expect(devices, hasLength(1));
      expect(devices.single.id, 'pixel-9');
      expect(client.lastType, 'emulator.devices');
      expect(client.lastPayload, <String, Object?>{'platform': 'android'});
      expect(client.lastTimeout, const Duration(seconds: 45));
    });

    test('parses per-platform backend availability', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{
        'ok': true,
        'platforms': <String, Object?>{
          'android': <String, Object?>{'available': true, 'message': 'Ready'},
          'ios': <String, Object?>{
            'available': false,
            'message': 'iOS Requires Apple Silicon.',
          },
        },
      });
      final service = MobileEmulatorService(client);

      final capabilities = await service.capabilities();

      expect(capabilities[MobileEmulatorPlatform.android]?.available, true);
      expect(capabilities[MobileEmulatorPlatform.ios]?.available, false);
      expect(
        capabilities[MobileEmulatorPlatform.ios]?.message,
        'iOS Requires Apple Silicon.',
      );
      expect(client.lastTimeout, const Duration(seconds: 45));
    });

    test('allows host-side virtual device boot to finish', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{
        'ok': true,
        'session': <String, Object?>{
          'id': 'tab-1',
          'state': 'ready',
          'platform': 'android',
          'deviceId': 'android:pixel-9',
        },
      });
      final service = MobileEmulatorService(client);

      await service.acquire(
        const MobileEmulatorTarget(tabId: 'tab-1', workspaceId: 'workspace-1'),
      );

      expect(client.lastTimeout, const Duration(minutes: 7));
    });

    test('keeps pointer coordinates normalized on the wire', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{'ok': true});
      final service = MobileEmulatorService(client);

      await service.pointer(
        target: const MobileEmulatorTarget(
          tabId: 'tab-1',
          workspaceId: 'workspace-1',
        ),
        type: 'move',
        x: -1,
        y: 2,
      );

      expect(client.lastType, 'emulator.pointer');
      expect(client.lastPayload, <String, Object?>{
        'tabId': 'tab-1',
        'interactive': true,
        'type': 'move',
        'x': 0.0,
        'y': 1.0,
      });
    });

    test('sends interactive named keys through the acquired surface', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{'ok': true});
      final service = MobileEmulatorService(client);
      const target = MobileEmulatorTarget(
        tabId: 'tab-1',
        workspaceId: 'workspace-1',
      );

      await service.key(target: target, key: 'backspace');

      expect(client.lastType, 'emulator.key');
      expect(client.lastPayload, <String, Object?>{
        'tabId': 'tab-1',
        'interactive': true,
        'key': 'backspace',
      });
    });

    test('surfaces structured operational failures', () async {
      final client = _FakeRuntimeHostClient(<String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'dependency_missing',
          'message': 'Android SDK Missing',
          'nextSteps': <String>['Install Android Studio.'],
        },
      });
      final service = MobileEmulatorService(client);

      await expectLater(
        service.devices(),
        throwsA(
          isA<MobileEmulatorException>()
              .having((error) => error.code, 'code', 'dependency_missing')
              .having((error) => error.nextSteps, 'nextSteps', <String>[
                'Install Android Studio.',
              ]),
        ),
      );
    });

    test('requires the additive host capability before emulator verbs', () {
      final service = MobileEmulatorService(
        _FakeRuntimeHostClient(<String, Object?>{
          'ok': true,
        }, supportsEmulator: false),
      );

      expect(
        service.devices(),
        throwsA(
          isA<MobileEmulatorException>().having(
            (error) => error.code,
            'code',
            'runtime_update_required',
          ),
        ),
      );
    });
  });

  test('workspace emulator payload rejects unknown schemas', () {
    const payload = WorkspaceMobileEmulatorPayload(
      platform: MobileEmulatorPlatform.ios,
      deviceId: 'simulator-1',
    );

    expect(
      WorkspaceMobileEmulatorPayload.fromJson(payload.toJson())?.deviceId,
      'simulator-1',
    );
    expect(
      WorkspaceMobileEmulatorPayload.fromJson(<String, Object?>{
        ...payload.toJson(),
        'schemaVersion': 2,
      }),
      isNull,
    );
  });

  test('runtime release stays parked while the surface is hidden', () {
    expect(
      resolveMobileEmulatorRuntimeChange(reason: 'released', leaseHeld: false),
      MobileEmulatorRuntimeChangeAction.ignore,
    );
    expect(
      resolveMobileEmulatorRuntimeChange(reason: 'released', leaseHeld: true),
      MobileEmulatorRuntimeChangeAction.refresh,
    );
  });

  test('runtime shutdown requires an explicit retry', () {
    expect(
      resolveMobileEmulatorRuntimeChange(reason: 'shutdown', leaseHeld: true),
      MobileEmulatorRuntimeChangeAction.stopped,
    );
  });

  test('decoded video rotation updates the interactive aspect ratio', () {
    expect(
      mobileEmulatorDecodedAspectRatio(width: 1080, height: 2400, rotation: 0),
      1080 / 2400,
    );
    expect(
      mobileEmulatorDecodedAspectRatio(width: 1080, height: 2400, rotation: 90),
      2400 / 1080,
    );
    expect(
      mobileEmulatorDecodedAspectRatio(width: null, height: 2400, rotation: 0),
      isNull,
    );
  });

  test('domain models expose readiness and concise failure text', () {
    final session = MobileEmulatorSession.fromJson(
      _sessionResponse('ready', 'http://127.0.0.1/stream')['session'],
    );
    const failure = MobileEmulatorException(
      code: 'stream_failed',
      message: 'The Stream Failed.',
    );

    expect(session?.isReady, isTrue);
    expect(failure.toString(), 'The Stream Failed.');
  });

  test(
    'reconnect invalidates support detection for the replacement host',
    () async {
      final events = StreamController<RuntimeHostEvent>.broadcast();
      final client = _FakeRuntimeHostClient(<String, Object?>{
        'ok': true,
        'items': <Object?>[],
      }, events: events.stream);
      final service = MobileEmulatorService(client);

      await service.devices();
      expect(client.statusRequests, 1);
      events.add(
        const RuntimeHostEvent(
          aleraRuntimeHostConnectedEvent,
          <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await service.devices();

      expect(client.statusRequests, 2);
      await events.close();
    },
  );

  test(
    'acquire waits for an in-flight release and refreshes the stream',
    () async {
      final client = _LeaseRaceRuntimeHostClient();
      final coordinator = MobileEmulatorLeaseCoordinator(
        MobileEmulatorService(client),
      );
      const target = MobileEmulatorTarget(
        tabId: 'tab-1',
        workspaceId: 'workspace-1',
      );

      await coordinator.acquire(target);
      final suspend = coordinator.suspend(target.tabId);
      await client.releaseStarted.future;
      final resumed = coordinator.acquire(target);
      client.releaseResult.complete(_sessionResponse('parked', null));

      await suspend;
      final session = await resumed;

      expect(client.acquireRequests, 2);
      expect(session.stream?.url.toString(), 'http://127.0.0.1/stream-2');
      coordinator.dispose();
    },
  );
}

class _FakeRuntimeHostClient implements RuntimeHostClient {
  _FakeRuntimeHostClient(
    this.response, {
    this.supportsEmulator = true,
    this.events = const Stream<RuntimeHostEvent>.empty(),
  });

  final Object? response;
  final bool supportsEmulator;
  final Stream<RuntimeHostEvent> events;
  String? lastType;
  Map<String, Object?>? lastPayload;
  Duration? lastTimeout;
  int statusRequests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    lastType = type;
    lastPayload = payload;
    lastTimeout = timeout;
    if (type == 'status.get') {
      statusRequests += 1;
      return <String, Object?>{
        'runtimeCapabilities': <String>[
          if (supportsEmulator) aleraRuntimeHostMobileEmulatorCapability,
        ],
      };
    }
    return response;
  }
}

class _LeaseRaceRuntimeHostClient implements RuntimeHostClient {
  final Completer<void> releaseStarted = Completer<void>();
  final Completer<Object?> releaseResult = Completer<Object?>();
  int acquireRequests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    switch (type) {
      case 'status.get':
        return <String, Object?>{
          'runtimeCapabilities': <String>[
            aleraRuntimeHostMobileEmulatorCapability,
          ],
        };
      case 'emulator.acquire':
        acquireRequests += 1;
        return _sessionResponse(
          'ready',
          'http://127.0.0.1/stream-$acquireRequests',
        );
      case 'emulator.release':
        releaseStarted.complete();
        return releaseResult.future;
      default:
        return <String, Object?>{'ok': true};
    }
  }
}

Map<String, Object?> _sessionResponse(String state, String? streamUrl) =>
    <String, Object?>{
      'ok': true,
      'session': <String, Object?>{
        'id': 'tab-1',
        'tabId': 'tab-1',
        'workspaceId': 'workspace-1',
        'state': state,
        'platform': 'android',
        'deviceId': 'android:pixel-9',
        'deviceName': 'Pixel 9',
        if (streamUrl != null)
          'stream': <String, Object?>{
            'state': 'ready',
            'codec': 'h264',
            'url': streamUrl,
            'width': 1080,
            'height': 2400,
          },
      },
    };
