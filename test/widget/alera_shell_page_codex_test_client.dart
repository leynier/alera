part of 'alera_shell_page_test.dart';

final class _ShellCodexClient implements RuntimeHostClient {
  _ShellCodexClient({this.sharedQueues = false, this.unboundQueue = false});
  final bool unboundQueue;
  final bool sharedQueues;
  final List<String> cancelledTabs = [];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    if (sharedQueues && type == 'status.get') {
      return {
        'runtimeCapabilities': ['codexSharedQueueV1'],
      };
    }
    if (sharedQueues && type == 'codex.queue.get') {
      return {
        'threadId': unboundQueue ? '' : payload['tabId'],
        if (unboundQueue)
          'otherQueues': [
            {'threadId': 'previous', 'revision': 4},
          ],
        'revision': 1,
        'messages': [
          if (!unboundQueue) {'id': 'queued'},
        ],
      };
    }
    if (type == 'codex.queue.cancel') {
      if (unboundQueue) {
        expect(payload['expectedThreadId'], isNull);
        expect(payload['otherQueues'], [
          {'threadId': 'previous', 'revision': 4},
        ]);
      }
      cancelledTabs.add(payload['tabId']! as String);
    }
    return const <String, Object?>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
