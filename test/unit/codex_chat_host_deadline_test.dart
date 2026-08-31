import 'dart:async';

import 'package:alera/src/features/codex_chat/infra/codex_chat_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in [
    'codex.thread.fork',
    'codex.thread.edit',
    'codex.queue.reconcile',
  ]) {
    for (final rejected in [false, true]) {
      testWidgets(
        '$type preserves a late ${rejected ? "failure" : "response"}',
        (tester) async {
          final transport = _DelayedClient();
          final client = CodexChatHostClient(transport);
          addTearDown(client.dispose);
          Object? outcome;
          const payload = {
            'tabId': 'tab',
            'expectedThreadId': 'thread',
            'operationId': 'operation',
          };
          unawaited(
            client
                .request(type, payload)
                .then<void>(
                  (value) {
                    outcome = value;
                  },
                  onError: (Object error) {
                    outcome = error;
                  },
                ),
          );
          await tester.pump(const Duration(minutes: 4));
          expect(outcome, isNull);
          expect(transport.timeout, const Duration(minutes: 7));
          expect(transport.calls, 1);
          expect(transport.payload, payload);
          if (rejected) {
            transport.reply.completeError(StateError('Late rejection'));
          } else {
            transport.reply.complete({
              'tabId': 'forked',
              'operationId': 'operation',
            });
          }
          await tester.pump();
          expect(
            outcome,
            rejected
                ? isA<StateError>()
                : {'tabId': 'forked', 'operationId': 'operation'},
          );
          expect(transport.calls, 1);
        },
      );
    }
  }
  testWidgets('ordinary Codex requests keep their transport deadline', (
    tester,
  ) async {
    final transport = _DelayedClient();
    final client = CodexChatHostClient(transport);
    addTearDown(client.dispose);
    Object? error;
    unawaited(
      client
          .request('codex.queue.get')
          .then<void>(
            (_) {},
            onError: (Object value) {
              error = value;
            },
          ),
    );
    await tester.pump(const Duration(seconds: 21));
    expect(error, isA<TimeoutException>());
    expect(transport.timeout, isNull);
    expect(transport.calls, 1);
    transport.reply.complete({});
    await tester.pump();
  });
  testWidgets(
    'deferred history deadlines remain bounded without automatic retry',
    (tester) async {
      final transport = _DelayedClient();
      final client = CodexChatHostClient(transport);
      addTearDown(client.dispose);
      Object? error;
      unawaited(
        client
            .request('codex.thread.edit', {'operationId': 'operation'})
            .then<void>(
              (_) {},
              onError: (Object value) {
                error = value;
              },
            ),
      );
      await tester.pump(const Duration(minutes: 8));
      expect(error, isA<TimeoutException>());
      expect(transport.calls, 1);
      transport.reply.complete({});
      await tester.pump();
    },
  );
}

final class _DelayedClient implements RuntimeHostClient {
  final reply = Completer<Map<String, Object?>>();
  Duration? timeout;
  Map<String, Object?>? payload;
  var calls = 0;
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();
  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) {
    calls += 1;
    this.timeout = timeout;
    this.payload = payload;
    return reply.future.timeout(timeout ?? const Duration(seconds: 10));
  }
}
