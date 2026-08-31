part of 'codex_chat_controller_test.dart';

void registerCodexStopRevisionTests() {
  for (final shared in [false, true]) {
    test(
      'Stop captures the active turn without a shared pause revision: $shared',
      () async {
        final interrupt = Completer<Object?>();
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': shared ? ['codexSharedQueueV1'] : [],
                'queue': {'threadId': 'thread', 'revision': 1, 'messages': []},
                'snapshot': {'activeTurnId': 'turn', 'timelineCells': []},
              });
            }
            if (type == 'codex.queue.pause') {
              return Future.error(StateError('Queue revision changed'));
            }
            if (type == 'codex.turn.interrupt') return interrupt.future;
            return null;
          },
        );
        final container = ProviderContainer(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(
              _TestSettingsController.new,
            ),
          ],
        );
        addTearDown(() {
          client.dispose();
          container.dispose();
        });
        final provider = codexChatControllerProvider('stop');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await _settle();
        final controller = container.read(provider.notifier);
        final stopping = controller.stop();
        await _settle();
        await controller.stop();
        final requests = client.requests
            .where((request) => request.type == 'codex.turn.interrupt')
            .toList();
        expect(requests, hasLength(1));
        expect(requests.single.payload['turnId'], 'turn');
        if (shared) {
          expect(requests.single.payload['expectedThreadId'], 'thread');
        }
        expect(
          client.requests.where(
            (request) => request.type == 'codex.queue.pause',
          ),
          isEmpty,
        );
        if (!shared) expect(container.read(provider).queuePaused, isTrue);
        interrupt.complete({});
        await stopping;
      },
    );
  }
}
