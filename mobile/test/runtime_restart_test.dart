import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_restart_result.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/settings/presentation/host_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Client feature detects restart and parses a busy runtime', () async {
    final harness = await _RuntimeRestartHarness.start(busyOnSoftRestart: true);
    addTearDown(harness.dispose);
    final client = await MobileRuntimeClient.connect(harness.endpoint);
    addTearDown(client.dispose);

    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

    expect(client.supportsRuntimeRestart, isTrue);
    await expectLater(
      client.restartRuntime(),
      throwsA(
        isA<RuntimeRestartBusyException>()
            .having((error) => error.activeAgents, 'activeAgents', 2)
            .having((error) => error.activeSessions, 'activeSessions', 1),
      ),
    );

    final result = await client.restartRuntime(force: true);
    expect(result.forced, isTrue);
    expect(
      harness.requests.where((request) => request['type'] == 'host.restart'),
      hasLength(2),
    );
  });

  testWidgets('Host Settings confirms a busy restart before forcing it', (
    tester,
  ) async {
    final channel = _RuntimeRestartChannel();
    final client = MobileRuntimeClient.forTesting(channel);
    addTearDown(() async {
      await client.dispose();
      await channel.dispose();
    });
    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
    final host = PairedHostProfile(
      id: 'runtime-1',
      displayName: 'Alera Host',
      endpoint: 'ws://127.0.0.1:6768',
      runtimeId: 'runtime-1',
      deviceId: 'device-1',
      pairedAt: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostConnectionControllerProvider.overrideWith2(
            (_) => _TestHostConnection(client),
          ),
        ],
        child: MaterialApp(home: HostSettingsScreen(host: host)),
      ),
    );
    await _pumpUntil(tester, find.text('General'));
    await tester.scrollUntilVisible(find.text('fx Status'), 200);
    await tester.pump();

    expect(find.text('fx Status'), findsOneWidget);
    expect(
      find.text(
        'Report status through the built-in Herdr integration on macOS and Linux.',
      ),
      findsOneWidget,
    );

    await tester.fling(find.byType(ListView), const Offset(0, 3000), 2000);
    await tester.pumpAndSettle();

    expect(find.text('Restart Runtime'), findsOneWidget);
    await tester.tap(find.text('Restart Runtime'));
    await _pumpUntil(tester, find.text('Restart Runtime?'));
    expect(find.text('Restart Runtime?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restart Runtime').last);
    await _pumpUntil(tester, find.text('Force Restart Runtime?'));
    expect(find.text('Force Restart Runtime?'), findsOneWidget);
    expect(find.textContaining('2 open agent(s)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Force Restart'));
    await _pumpUntil(
      tester,
      find.text('Runtime restarting'),
      timeout: const Duration(seconds: 5),
    );

    final restartRequests = channel.requests
        .where((request) => request['type'] == 'host.restart')
        .toList(growable: false);
    expect(restartRequests, hasLength(2));
    expect(
      restartRequests.map(
        (request) => (request['payload']! as Map<String, Object?>)['force'],
      ),
      <Object?>[false, true],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList(growable: false);
      throw TimeoutException(
        'Widget was not found: $finder. Visible text: $visibleText',
      );
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final class _RuntimeRestartHarness {
  _RuntimeRestartHarness._(
    this._server,
    this._subscription,
    this.busyOnSoftRestart,
  );

  static Future<_RuntimeRestartHarness> start({
    required bool busyOnSoftRestart,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final _RuntimeRestartHarness harness;
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      harness._sockets.add(socket);
      socket.listen((raw) => harness._handle(socket, raw));
    });
    harness = _RuntimeRestartHarness._(server, subscription, busyOnSoftRestart);
    return harness;
  }

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;
  final bool busyOnSoftRestart;
  final List<WebSocket> _sockets = <WebSocket>[];
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  String get endpoint => 'ws://${_server.address.address}:${_server.port}';

  void _handle(WebSocket socket, Object? raw) {
    final request = jsonDecode(raw! as String) as Map<String, Object?>;
    requests.add(request);
    final type = request['type'];
    final payload = request['payload']! as Map<String, Object?>;
    if (type == 'host.restart' &&
        payload['force'] != true &&
        busyOnSoftRestart) {
      socket.add(
        jsonEncode(<String, Object?>{
          'id': request['id'],
          'ok': false,
          'error':
              'Runtime host has 2 active agent(s), 1 active terminal session(s), 0 active background job(s), and 0 active push subscription(s). Retry with --force to stop it.',
        }),
      );
      return;
    }
    socket.add(
      jsonEncode(<String, Object?>{
        'id': request['id'],
        'ok': true,
        'payload': switch (type) {
          'mobile.hello' => <String, Object?>{
            'runtimeCapabilities': <String>[
              mobilePortableSettingsCapability,
              runtimeHostRestartCapability,
            ],
          },
          'mobile.runtimeSettings.get' => <String, Object?>{
            'workspaceDirectory': null,
            'confirmProjectRemoval': true,
            'confirmWorkspaceRemoval': true,
            'agentStatusHooks': <String, bool>{},
            'agentQuotas': <String, Object?>{},
          },
          'host.restart' => <String, Object?>{
            'restarting': true,
            'forced': payload['force'] == true,
            'activeSessions': 1,
            'activeJobs': 0,
            'activeAgents': 2,
            'activePushSubscriptions': 0,
          },
          _ => <String, Object?>{},
        },
      }),
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

final class _TestHostConnection extends HostConnectionController {
  _TestHostConnection(this.client);

  final MobileRuntimeClient client;

  @override
  Future<MobileRuntimeClient> build(String hostId) async => client;

  @override
  Future<RuntimeRestartResult> restartRuntime({bool force = false}) =>
      client.restartRuntime(force: force);
}

final class _RuntimeRestartChannel implements WebSocketChannel {
  _RuntimeRestartChannel() {
    _outgoing.stream.listen(_handle);
  }

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast(sync: true);
  final StreamController<Object?> _outgoing =
      StreamController<Object?>.broadcast(sync: true);
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  void _handle(Object? raw) {
    final request = jsonDecode(raw! as String) as Map<String, Object?>;
    requests.add(request);
    final type = request['type'];
    final payload = request['payload']! as Map<String, Object?>;
    if (type == 'host.restart' && payload['force'] != true) {
      _incoming.add(
        jsonEncode(<String, Object?>{
          'id': request['id'],
          'ok': false,
          'error':
              'Runtime host has 2 active agent(s), 1 active terminal session(s), 0 active background job(s), and 0 active push subscription(s). Retry with --force to stop it.',
        }),
      );
      return;
    }
    _incoming.add(
      jsonEncode(<String, Object?>{
        'id': request['id'],
        'ok': true,
        'payload': switch (type) {
          'mobile.hello' => <String, Object?>{
            'runtimeCapabilities': <String>[
              mobilePortableSettingsCapability,
              runtimeHostRestartCapability,
            ],
          },
          'mobile.runtimeSettings.get' => <String, Object?>{
            'workspaceDirectory': null,
            'confirmProjectRemoval': true,
            'confirmWorkspaceRemoval': true,
            'agentStatusHooks': <String, bool>{},
            'agentQuotas': <String, Object?>{},
          },
          'host.restart' => <String, Object?>{
            'restarting': true,
            'forced': true,
            'activeSessions': 1,
            'activeJobs': 0,
            'activeAgents': 2,
            'activePushSubscriptions': 0,
          },
          _ => <String, Object?>{},
        },
      }),
    );
  }

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  late final WebSocketSink sink = _TestWebSocketSink(_outgoing.sink);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> dispose() async {
    await _incoming.close();
    await _outgoing.close();
  }
}

final class _TestWebSocketSink implements WebSocketSink {
  _TestWebSocketSink(this._sink);

  final StreamSink<Object?> _sink;

  @override
  Future<void> get done => _sink.done;

  @override
  void add(Object? data) => _sink.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<Object?> stream) => _sink.addStream(stream);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => _sink.close();
}
