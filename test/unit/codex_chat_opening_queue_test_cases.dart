part of 'codex_chat_controller_test.dart';

void registerCodexOpeningSubmissionTests() {
  test(
    'opening submissions wait for shared capability discovery and acceptance',
    () async {
      final open = Completer<Object?>();
      final receipt = Completer<Object?>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') return open.future;
          if (type == 'codex.queue.add') return receipt.future;
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_TestSettingsController.new),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = codexChatControllerProvider('opening');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      final controller = container.read(provider.notifier);
      final attachments = [
        const CodexInputAttachment(path: '/tmp/photo.png', isImage: true),
      ];
      var accepted = false;
      final first = controller.send('First', attachments: attachments).then((
        value,
      ) {
        accepted = value;
        return value;
      });
      final second = controller.send('Second');
      attachments.clear();
      await _settle();
      expect(accepted, isFalse);
      expect(
        client.requests.where(
          (request) =>
              request.type == 'codex.queue.add' ||
              request.type == 'codex.turn.start',
        ),
        isEmpty,
      );
      open.complete({
        'threadId': 'thread',
        'chatFeatures': ['codexSharedQueueV1'],
        'snapshot': {'timelineCells': <Object?>[]},
        'queue': {'threadId': 'thread', 'revision': 1, 'messages': <Object?>[]},
      });
      await _settle();
      expect(accepted, isFalse);
      final submissions = client.requests
          .where((request) => request.type == 'codex.queue.add')
          .toList();
      expect(submissions, hasLength(2));
      expect(
        submissions.map((request) => request.payload['expectedThreadId']),
        ['thread', 'thread'],
      );
      expect(
        (submissions[0].payload['input']! as List)
            .whereType<Map>()
            .where((item) => item['type'] == 'localImage')
            .single['path'],
        '/tmp/photo.png',
      );
      expect((submissions[0].payload['draft']! as Map)['text'], 'First');
      expect((submissions[1].payload['draft']! as Map)['text'], 'Second');
      receipt.complete({
        'threadId': 'thread',
        'revision': 2,
        'messages': <Object?>[],
      });
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );
    },
  );

  for (final failure in ['open', 'submission', 'dispose']) {
    test('opening submission is not accepted after $failure failure', () async {
      final open = Completer<Object?>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') return open.future;
          if (type == 'codex.queue.add') {
            return Future.error(StateError('Queue rejected'));
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_TestSettingsController.new),
        ],
      );
      var disposed = false;
      addTearDown(() {
        client.dispose();
        if (!disposed) container.dispose();
      });
      final provider = codexChatControllerProvider('opening');
      container.listen(provider, (_, _) {});
      final sending = container.read(provider.notifier).send('Keep my draft');
      if (failure == 'open') {
        open.completeError(StateError('Open rejected'));
      } else if (failure == 'dispose') {
        container.dispose();
        disposed = true;
      } else {
        open.complete({
          'threadId': 'thread',
          'chatFeatures': ['codexSharedQueueV1'],
          'snapshot': {'timelineCells': <Object?>[]},
          'queue': {
            'threadId': 'thread',
            'revision': 1,
            'messages': <Object?>[],
          },
        });
      }
      expect(await sending, isFalse);
      if (failure != 'submission') {
        expect(
          client.requests.where(
            (request) =>
                request.type == 'codex.queue.add' ||
                request.type == 'codex.turn.start',
          ),
          isEmpty,
        );
      }
    });
  }
}
