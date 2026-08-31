import 'dart:async';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
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
          final client = transport;
          Object? outcome;
          const payload = {
            'tabId': 'tab',
            'expectedThreadId': 'thread',
            'operationId': 'operation',
          };
          unawaited(
            client
                .codexRequest(type, payload)
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
    final client = transport;
    Object? error;
    unawaited(
      client
          .codexRequest('codex.queue.get')
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
      final client = transport;
      Object? error;
      unawaited(
        client
            .codexRequest('codex.thread.edit', {'operationId': 'operation'})
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

final class _DelayedClient with MobileRuntimeCodexRequests {
  final reply = Completer<Map<String, Object?>>();
  Duration? timeout;
  Map<String, Object?>? payload;
  var calls = 0;
  @override
  bool get supportsCodexChat => true;
  @override
  bool get supportsCodexGoals => false;
  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) {
    calls += 1;
    this.timeout = timeout;
    this.payload = payload;
    return reply.future.timeout(timeout ?? const Duration(seconds: 20));
  }
}
