import 'dart:async';

import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  testWidgets(
    'does not register a refresh timer after the controller is disposed',
    (tester) async {
      final client = _FakeMobileRuntimeClient();
      final clientReady = Completer<MobileRuntimeClient>();
      final container = ProviderContainer(
        overrides: [
          hostConnectionControllerProvider.overrideWith2(
            (_) => _FakeHostConnection(clientReady.future),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final provider = agentQuotaControllerProvider('host-disposed-build');
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      final result = container.read(provider.future);
      subscription.close();
      container.dispose();

      clientReady.complete(client);
      await result;
      await tester.pump(mobileQuotaRefreshInterval);
    },
  );

  testWidgets('does not invalidate the quota controller after disposal', (
    tester,
  ) async {
    final client = _FakeMobileRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        hostConnectionControllerProvider.overrideWith2(
          (_) => _FakeHostConnection(Future<MobileRuntimeClient>.value(client)),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final hostSubscription = container.listen(
      hostConnectionControllerProvider('host-1'),
      (_, _) {},
      fireImmediately: true,
    );
    final quotaSubscription = container.listen(
      agentQuotaControllerProvider('host-1'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(hostSubscription.close);
    addTearDown(quotaSubscription.close);
    await tester.pump();
    expect(
      container.read(agentQuotaControllerProvider('host-1')).hasValue,
      isTrue,
    );

    quotaSubscription.close();
    hostSubscription.close();
    container.dispose();
    await tester.pump(mobileQuotaRefreshInterval);
  });
}

final class _FakeHostConnection extends HostConnectionController {
  _FakeHostConnection(this.client);

  final Future<MobileRuntimeClient> client;

  @override
  Future<MobileRuntimeClient> build(String hostId) => client;
}

final class _FakeMobileRuntimeClient extends MobileRuntimeClient {
  _FakeMobileRuntimeClient() : super.forTesting(_PassiveWebSocketChannel());

  @override
  bool get supportsAgentQuotas => true;

  @override
  Future<QuotaSnapshotState> fetchAgentQuotas({bool forceRefresh = false}) {
    return Future<QuotaSnapshotState>.value(
      QuotaSnapshotState(
        snapshots: const <QuotaSnapshot>[],
        environment: const <String, bool>{},
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
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
