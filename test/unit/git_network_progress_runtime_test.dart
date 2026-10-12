import 'package:alera/src/shared/infra/git/git_exception.dart';

import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/runtime_git_backend.dart';
import 'package:flutter_test/flutter_test.dart';

class Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool capable = true;
  bool disconnect = false;
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();
  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    expect(capability, 'gitOperationsProgressV1');
    return capable;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add((type, payload));
    if (disconnect) throw StateError('host disconnected');
    return type == 'git.networkProgress'
        ? {'line': 'Writing objects: 100%'}
        : null;
  }
}

void main() {
  test(
    'progress stays correlated to the original remote workspace and path',
    () async {
      final client = Client();
      final lines = <String>[];
      await RuntimeGitBackend(
        client,
        workspaceId: 'remote',
      ).networkWithProgress('/checkout', push: true, onOutput: lines.add);
      expect(lines, ['Writing objects: 100%']);
      expect(client.calls.map((call) => call.$1), [
        'git.pushWithProgress',
        'git.networkProgress',
      ]);
      expect(
        client.calls.first.$2['operationId'],
        client.calls.last.$2['operationId'],
      );
      for (final call in client.calls) {
        expect(call.$2['workspaceId'], 'remote');
        expect(call.$2['path'], '/checkout');
      }
    },
  );
  test(
    'older hosts preserve the existing operation without unsupported RPC',
    () async {
      final client = Client()..capable = false;
      await RuntimeGitBackend(client, workspaceId: 'old').networkWithProgress(
        '/checkout',
        push: false,
        onOutput: (_) => fail('unexpected output'),
      );
      expect(client.calls.single.$1, 'git.pull');
    },
  );
  test('disconnect fails once and does not repeat a network write', () async {
    final client = Client()..disconnect = true;
    await expectLater(
      RuntimeGitBackend(
        client,
        workspaceId: 'remote',
      ).networkWithProgress('/checkout', push: true, onOutput: (_) {}),
      throwsA(isA<GitInternalException>()),
    );
    expect(client.calls.single.$1, 'git.pushWithProgress');
  });
}
