import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/alera_mobile_app.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/memory_host_repository.dart';

void main() {
  test('Pairing Result Uses Host Name For Stored Profile', () {
    final profile = PairedHostProfile.fromPairingResult(
      PairingOffer(
        version: aleraMobileProtocolVersion,
        pairingId: 'pairing',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        hostName: 'Alera Workstation',
        pairingSecret: 'secret',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
      const PairedDeviceCredentials(
        deviceId: 'device',
        displayName: 'Alera Mobile',
        runtimeId: 'runtime',
        deviceToken: 'token',
      ),
    );

    expect(profile.displayName, 'Alera Workstation');
  });

  testWidgets('Shows Stored Paired Host', (WidgetTester tester) async {
    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime',
        displayName: 'Alera Dev',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        deviceId: 'device',
        pairedAt: DateTime.now().toUtc(),
      ),
      'device-token',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostRepositoryProvider.overrideWithValue(repository),
          // Home quotas watch host connections; keep the smoke test offline.
          hostConnectionControllerProvider.overrideWith2(
            (_) => _OfflineHostConnection(),
          ),
        ],
        child: const AleraMobileApp(),
      ),
    );
    expect(find.text('Loading Alera'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Alera Dev'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(await repository.readDeviceToken('runtime'), 'device-token');
  });

  testWidgets('Shows Ready after a host connection succeeds', (
    WidgetTester tester,
  ) async {
    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime',
        displayName: 'Alera Dev',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        deviceId: 'device',
        pairedAt: DateTime.now().toUtc(),
      ),
      'device-token',
    );
    final channel = _TestWebSocketChannel();
    final client = MobileRuntimeClient.forTesting(channel);
    addTearDown(() async {
      await client.dispose();
      await channel.dispose();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostRepositoryProvider.overrideWithValue(repository),
          hostConnectionControllerProvider.overrideWith2(
            (_) => _ReadyHostConnection(client),
          ),
        ],
        child: const AleraMobileApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Unavailable'), findsNothing);
  });
}

class _OfflineHostConnection extends HostConnectionController {
  @override
  Future<MobileRuntimeClient> build(String hostId) async {
    throw UnsupportedError('Offline In Test');
  }
}

class _ReadyHostConnection extends HostConnectionController {
  _ReadyHostConnection(this.client);

  final MobileRuntimeClient client;

  @override
  Future<MobileRuntimeClient> build(String hostId) async => client;
}

class _TestWebSocketChannel implements WebSocketChannel {
  _TestWebSocketChannel() {
    _outgoing.stream.listen((raw) {
      final message = jsonDecode(raw! as String) as Map<String, Object?>;
      _incoming.add(
        jsonEncode(<String, Object?>{
          'id': message['id'],
          'ok': true,
          'payload': <String, Object?>{},
        }),
      );
    });
  }

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast();
  final StreamController<Object?> _outgoing =
      StreamController<Object?>.broadcast();

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

class _TestWebSocketSink implements WebSocketSink {
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
