import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_qr_code.dart';
import 'package:alera/src/features/mobile_devices/application/mobile_access_providers.dart';
import 'package:alera/src/features/mobile_devices/infra/runtime_mobile_access_repository.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_devices_pane.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<_FakeMobileRuntimeHostClient> pumpPane(
    WidgetTester tester, {
    _FakeMobileRuntimeHostClient? client,
  }) async {
    client ??= _FakeMobileRuntimeHostClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileAccessRepositoryProvider.overrideWithValue(
            RuntimeMobileAccessRepository(client),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MobileDevicesSettingsPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('renders gateway, offers, and device groups', (tester) async {
    await pumpPane(tester);

    expect(find.text('Mobile Gateway'), findsOneWidget);
    expect(find.text('Link A Device'), findsOneWidget);
    expect(find.text('Active Pairing Offers'), findsOneWidget);
    expect(find.text('Paired Devices'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.textContaining('ws://127.0.0.1:6768'), findsOneWidget);
  });

  testWidgets('renders the connection mode selector segments', (tester) async {
    await pumpPane(tester);

    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('Tailscale'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    // Loopback mode keeps the manual bind host field hidden.
    expect(find.text('Bind Host'), findsNothing);
  });

  testWidgets('selecting tailscale sends only the endpoint mode', (
    tester,
  ) async {
    final client = _FakeMobileRuntimeHostClient()
      ..tailscaleStatus = <String, Object?>{
        'detected': true,
        'running': true,
        'tailnetIp': '100.101.102.103',
      };
    await pumpPane(tester, client: client);

    await tester.tap(find.text('Tailscale'));
    await tester.pumpAndSettle();

    expect(client.requestsOfType('mobile.settings.update').single, {
      'endpointMode': 'tailscale',
    });
    expect(find.text('Tailscale Status'), findsOneWidget);
    expect(find.text('Running · 100.101.102.103'), findsOneWidget);
  });

  testWidgets('tailscale mode hides the pairing endpoint field', (
    tester,
  ) async {
    final client = _FakeMobileRuntimeHostClient()
      ..endpointMode = 'tailscale'
      ..bindHost = '100.101.102.103'
      ..tailscaleStatus = <String, Object?>{
        'detected': true,
        'running': true,
        'tailnetIp': '100.101.102.103',
      };
    await pumpPane(tester, client: client);

    expect(find.text('Endpoint'), findsNothing);
    expect(find.text('Tailscale Status'), findsOneWidget);
  });

  testWidgets('runtime errors from mode selection surface in the pane', (
    tester,
  ) async {
    final client = _FakeMobileRuntimeHostClient()..failSettingsUpdate = true;
    await pumpPane(tester, client: client);

    await tester.tap(find.text('Tailscale'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not running'), findsOneWidget);
  });

  testWidgets('legacy custom bind hosts render as manual mode', (tester) async {
    final client = _FakeMobileRuntimeHostClient()..bindHost = '192.168.1.10';
    await pumpPane(tester, client: client);

    expect(find.text('Bind Host'), findsOneWidget);
  });

  testWidgets('revoke asks for confirmation and calls the runtime', (
    tester,
  ) async {
    final client = await pumpPane(tester);

    await tester.ensureVisible(find.byTooltip('Revoke Device'));
    await tester.tap(find.byTooltip('Revoke Device'));
    await tester.pumpAndSettle();
    expect(find.textContaining('loses access'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(client.requestsOfType('mobile.device.revoke'), hasLength(1));
    expect(
      client.requestsOfType('mobile.device.revoke').single['id'],
      'device-1',
    );
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.byTooltip('Delete Device'), findsOneWidget);
    expect(find.byTooltip('Revoke Device'), findsNothing);
    expect(find.byTooltip('Rename Device'), findsNothing);
  });

  testWidgets('delete asks for confirmation and removes a revoked device', (
    tester,
  ) async {
    final client = _FakeMobileRuntimeHostClient()..deviceRevoked = true;
    await pumpPane(tester, client: client);

    await tester.ensureVisible(find.byTooltip('Delete Device'));
    await tester.tap(find.byTooltip('Delete Device'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Permanently removes'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(client.requestsOfType('mobile.device.delete'), hasLength(1));
    expect(
      client.requestsOfType('mobile.device.delete').single['id'],
      'device-1',
    );
    expect(find.text('No paired devices'), findsOneWidget);
  });

  testWidgets('rename dialog submits the trimmed name', (tester) async {
    final client = await pumpPane(tester);

    await tester.ensureVisible(find.byTooltip('Rename Device'));
    await tester.tap(find.byTooltip('Rename Device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  New Phone  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    final payload = client.requestsOfType('mobile.device.rename').single;
    expect(payload['id'], 'device-1');
    expect(payload['displayName'], 'New Phone');
  });

  testWidgets('invalid endpoint blocks offer creation with an error', (
    tester,
  ) async {
    final client = await pumpPane(tester);

    final endpointField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.hintText?.startsWith('wss://') ?? false),
    );
    await tester.ensureVisible(endpointField);
    await tester.enterText(endpointField, 'ws://192.168.1.50:6768');
    await tester.pump();
    final generateButton = find.widgetWithText(FilledButton, 'Generate');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Endpoints outside loopback or a Tailscale Tailnet must use wss://',
      ),
      findsOneWidget,
    );
    expect(client.requestsOfType('mobile.pairing.create'), isEmpty);
  });

  testWidgets('generating an offer opens the QR dialog', (tester) async {
    final client = await pumpPane(tester);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Generate'));
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();

    expect(client.requestsOfType('mobile.pairing.create'), hasLength(1));
    expect(find.byType(AleraQrCode), findsOneWidget);
    expect(find.text('Copy Pairing JSON'), findsOneWidget);

    // Close the dialog so its countdown timer is disposed.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AleraQrCode), findsNothing);
  });

  testWidgets('cancelling an active offer confirms and refreshes', (
    tester,
  ) async {
    final client = await pumpPane(tester);

    await tester.ensureVisible(find.byTooltip('Cancel Offer'));
    await tester.tap(find.byTooltip('Cancel Offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Offer'));
    await tester.pumpAndSettle();

    expect(client.requestsOfType('mobile.pairing.cancel'), hasLength(1));
    expect(find.text('No active offers'), findsOneWidget);
  });
}

final class _FakeMobileRuntimeHostClient implements RuntimeHostClient {
  final List<_Request> requests = <_Request>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  bool deviceRevoked = false;
  bool deviceDeleted = false;
  String deviceName = 'Phone';
  bool offerCancelled = false;
  String bindHost = '127.0.0.1';
  String endpointMode = 'loopback';
  Map<String, Object?>? tailscaleStatus;
  bool failSettingsUpdate = false;

  List<Map<String, Object?>> requestsOfType(String type) {
    return <Map<String, Object?>>[
      for (final request in requests)
        if (request.type == type) request.payload,
    ];
  }

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(_Request(type, Map<String, Object?>.from(payload)));
    switch (type) {
      case 'mobile.status.get':
        return _status();
      case 'mobile.device.revoke':
        deviceRevoked = true;
        _events.add(
          const RuntimeHostEvent('mobileDevicesChanged', <String, Object?>{}),
        );
        return <String, Object?>{};
      case 'mobile.device.delete':
        deviceDeleted = true;
        _events.add(
          const RuntimeHostEvent('mobileDevicesChanged', <String, Object?>{}),
        );
        return <String, Object?>{};
      case 'mobile.device.rename':
        deviceName = payload['displayName']! as String;
        _events.add(
          const RuntimeHostEvent('mobileDevicesChanged', <String, Object?>{}),
        );
        return _device();
      case 'mobile.pairing.cancel':
        offerCancelled = true;
        _events.add(
          const RuntimeHostEvent('mobilePairingsChanged', <String, Object?>{}),
        );
        return <String, Object?>{};
      case 'mobile.pairing.create':
        return <String, Object?>{
          'v': 1,
          'pairingId': 'offer-2',
          'endpoint': 'ws://127.0.0.1:6768',
          'runtimeId': 'runtime-1',
          'hostName': 'Test Host',
          'pairingSecret': 'secret',
          'serverPublicKeyB64': null,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        };
      case 'mobile.settings.update':
        if (failSettingsUpdate) {
          throw StateError('tailscale is installed but not running');
        }
        final requestedMode = payload['endpointMode'];
        if (requestedMode is String) {
          endpointMode = requestedMode;
          bindHost = requestedMode == 'tailscale'
              ? '100.101.102.103'
              : '127.0.0.1';
        }
        _events.add(
          const RuntimeHostEvent('mobileSettingsChanged', <String, Object?>{}),
        );
        return <String, Object?>{
          'enabled': payload['enabled'] ?? true,
          'bindHost': payload['bindHost'] ?? bindHost,
          'port': payload['port'] ?? 6768,
          'endpointMode': endpointMode,
        };
      default:
        throw UnimplementedError(type);
    }
  }

  Map<String, Object?> _status() {
    return <String, Object?>{
      'protocolVersion': 1,
      'settings': <String, Object?>{
        'enabled': true,
        'bindHost': bindHost,
        'port': 6768,
        'endpointMode': endpointMode,
      },
      if (tailscaleStatus != null) 'tailscale': tailscaleStatus,
      'devices': deviceDeleted ? const <Object?>[] : <Object?>[_device()],
      'activePairings': offerCancelled
          ? const <Object?>[]
          : <Object?>[
              <String, Object?>{
                'id': 'offer-1',
                'endpoint': 'ws://127.0.0.1:6768',
                'expectedDeviceName': null,
                'createdAt': '2026-07-17T00:00:00.000Z',
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
              },
            ],
      'runtimeHostActive': true,
    };
  }

  Map<String, Object?> _device() {
    return <String, Object?>{
      'id': 'device-1',
      'displayName': deviceName,
      'permission': 'fullControl',
      'pairedAt': '2026-07-15T00:00:00.000Z',
      'lastSeenAt': '2026-07-16T12:00:00.000Z',
      'revokedAt': deviceRevoked ? '2026-07-17T00:00:00.000Z' : null,
    };
  }
}

final class _Request {
  const _Request(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}
