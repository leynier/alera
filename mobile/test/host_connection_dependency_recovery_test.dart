import 'dart:async';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('Dependents replace a client across error and loading states', () async {
    final firstClient = MobileRuntimeClient.forTesting(
      _PassiveWebSocketChannel(),
    );
    final secondClient = MobileRuntimeClient.forTesting(
      _PassiveWebSocketChannel(),
    );
    addTearDown(firstClient.dispose);
    addTearDown(secondClient.dispose);

    late _MutableHostConnection connection;
    final container = ProviderContainer(
      overrides: [
        hostConnectionControllerProvider.overrideWith2((_) {
          connection = _MutableHostConnection(firstClient);
          return connection;
        }),
      ],
    );
    addTearDown(container.dispose);
    final dependentProvider = terminalClientProvider('runtime-1');
    final dependent = container.listen(dependentProvider, (_, _) {});
    addTearDown(dependent.close);

    expect(await container.read(dependentProvider.future), same(firstClient));
    connection.fail();
    await pumpEventQueue();
    connection.beginReconnect();
    await pumpEventQueue();
    connection.completeReconnect(secondClient);

    await _waitUntil(
      () => identical(container.read(dependentProvider).value, secondClient),
    );
    expect(container.read(dependentProvider).requireValue, same(secondClient));
  });
}

final class _MutableHostConnection extends HostConnectionController {
  _MutableHostConnection(this.initialClient);

  final MobileRuntimeClient initialClient;

  @override
  Future<MobileRuntimeClient> build(String hostId) async => initialClient;

  void fail() {
    state = AsyncError<MobileRuntimeClient>(
      const RuntimeConnectionLost(),
      StackTrace.current,
    );
  }

  void beginReconnect() {
    state = const AsyncLoading<MobileRuntimeClient>();
  }

  void completeReconnect(MobileRuntimeClient client) {
    state = AsyncData<MobileRuntimeClient>(client);
  }
}

final class _PassiveWebSocketChannel implements WebSocketChannel {
  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast(sync: true);
  final StreamController<Object?> _outgoing =
      StreamController<Object?>.broadcast(sync: true);

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
  late final WebSocketSink sink = _PassiveWebSocketSink(_outgoing.sink);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PassiveWebSocketSink implements WebSocketSink {
  _PassiveWebSocketSink(this._sink);

  final StreamSink<Object?> _sink;

  @override
  Future<void> get done => _sink.done;

  @override
  void add(Object? data) => _sink.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _sink.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<Object?> stream) => _sink.addStream(stream);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => _sink.close();
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
