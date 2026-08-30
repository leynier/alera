import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/settings/application/host_tools_controllers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('Mounted skill install publishes progress and completion', () async {
    final channel = _SkillInstallChannel();
    addTearDown(channel.dispose);
    final client = await _authenticatedClient(channel);
    final container = _containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final provider = skillInstallControllerProvider('host-1', 'cli');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final install = container.read(provider.notifier).install('npx');
    final request = await channel.installRequest;
    final operationId = _operationId(request);
    channel.emitProgress(operationId, 'Preparing install');
    await pumpEventQueue();

    expect(
      container.read(provider),
      isA<SkillInstallState>()
          .having((value) => value.phase, 'phase', 'installing')
          .having((value) => value.message, 'message', 'Preparing install'),
    );

    channel.completeInstall(succeeded: true, summary: 'Skill installed');
    await install;

    expect(
      container.read(provider),
      isA<SkillInstallState>()
          .having((value) => value.phase, 'phase', 'completed')
          .having((value) => value.message, 'message', 'Skill installed')
          .having((value) => value.result?.succeeded, 'succeeded', isTrue),
    );
  });

  test('Mounted skill install publishes request errors', () async {
    final channel = _SkillInstallChannel();
    addTearDown(channel.dispose);
    final client = await _authenticatedClient(channel);
    final container = _containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final provider = skillInstallControllerProvider('host-1', 'cli');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final install = container.read(provider.notifier).install('npx');
    await channel.installRequest;
    channel.failInstall('Runner failed');
    await install;

    expect(
      container.read(provider),
      isA<SkillInstallState>()
          .having((value) => value.phase, 'phase', 'failed')
          .having(
            (value) => value.message,
            'message',
            contains('Runner failed'),
          ),
    );
  });

  test('Completion after disposal does not write provider state', () async {
    final channel = _SkillInstallChannel();
    addTearDown(channel.dispose);
    final client = await _authenticatedClient(channel);
    final container = _containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final provider = skillInstallControllerProvider('host-1', 'cli');
    final subscription = container.listen(provider, (_, _) {});

    final install = container.read(provider.notifier).install('npx');
    await channel.installRequest;
    subscription.close();
    await pumpEventQueue();
    expect(container.exists(provider), isFalse);

    channel.completeInstall(succeeded: true, summary: 'Skill installed');

    await expectLater(install, completes);
  });

  test('Request error after disposal does not write provider state', () async {
    final channel = _SkillInstallChannel();
    addTearDown(channel.dispose);
    final client = await _authenticatedClient(channel);
    final container = _containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final provider = skillInstallControllerProvider('host-1', 'cli');
    final subscription = container.listen(provider, (_, _) {});

    final install = container.read(provider.notifier).install('npx');
    final request = await channel.installRequest;
    subscription.close();
    await pumpEventQueue();
    expect(container.exists(provider), isFalse);

    channel.emitProgress(_operationId(request), 'Install still running');
    channel.failInstall('Runner failed');

    await expectLater(install, completes);
  });
}

ProviderContainer _containerFor(MobileRuntimeClient client) {
  return ProviderContainer(
    overrides: [
      hostConnectionControllerProvider.overrideWith2(
        (_) => _TestHostConnection(client),
      ),
    ],
  );
}

Future<MobileRuntimeClient> _authenticatedClient(
  _SkillInstallChannel channel,
) async {
  final client = MobileRuntimeClient.forTesting(channel);
  await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
  return client;
}

String _operationId(Map<String, Object?> request) {
  final payload = request['payload']! as Map<String, Object?>;
  return payload['operationId']! as String;
}

final class _TestHostConnection(final MobileRuntimeClient client)
    extends HostConnectionController {
  @override
  Future<MobileRuntimeClient> build(String hostId) async => client;
}

final class _SkillInstallChannel() implements WebSocketChannel {
  this {
    _outgoing.stream.listen(_handleRequest);
  }

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast(sync: true);
  final StreamController<Object?> _outgoing =
      StreamController<Object?>.broadcast(sync: true);
  final Completer<Map<String, Object?>> _installRequest =
      Completer<Map<String, Object?>>();
  Map<String, Object?>? _pendingInstall;

  Future<Map<String, Object?>> get installRequest => _installRequest.future;

  void _handleRequest(Object? raw) {
    final request = jsonDecode(raw! as String) as Map<String, Object?>;
    if (request['type'] == 'mobile.hello') {
      _respond(request, <String, Object?>{
        'runtimeCapabilities': <String>[mobileHostToolsCapability],
      });
      return;
    }
    if (request['type'] == 'agentSkill.install') {
      _pendingInstall = request;
      _installRequest.complete(request);
      return;
    }
    _respond(request, const <String, Object?>{});
  }

  void emitProgress(String operationId, String message) {
    _incoming.add(
      jsonEncode(<String, Object?>{
        'event': 'agentSkillInstallProgress',
        'payload': <String, Object?>{
          'operationId': operationId,
          'phase': 'installing',
          'message': message,
        },
      }),
    );
  }

  void completeInstall({required bool succeeded, required String summary}) {
    _respond(_takePendingInstall(), <String, Object?>{
      'succeeded': succeeded,
      'summary': summary,
    });
  }

  void failInstall(String message) {
    final request = _takePendingInstall();
    _incoming.add(
      jsonEncode(<String, Object?>{
        'id': request['id'],
        'ok': false,
        'error': message,
      }),
    );
  }

  Map<String, Object?> _takePendingInstall() {
    final request = _pendingInstall;
    _pendingInstall = null;
    if (request == null) {
      throw StateError('No skill install request is pending.');
    }
    return request;
  }

  void _respond(Map<String, Object?> request, Map<String, Object?> payload) {
    _incoming.add(
      jsonEncode(<String, Object?>{
        'id': request['id'],
        'ok': true,
        'payload': payload,
      }),
    );
  }

  Future<void> dispose() async {
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
    if (!_outgoing.isClosed) {
      await _outgoing.close();
    }
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
}

final class _TestWebSocketSink(final StreamSink<Object?> _sink)
    implements WebSocketSink {
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
