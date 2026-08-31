part of 'codex_chat_surface_test.dart';

void _registerCodexQueueIdentityTests() {
  testWidgets('queue removal keeps the rendered ID after a concurrent update', (
    tester,
  ) async {
    Map<String, Object?> queue(int revision, List<String> ids) => {
      'tabId': 'codex-tab',
      'threadId': 'thread',
      'revision': revision,
      'paused': true,
      'messages': [
        for (final id in ids)
          {
            'id': id,
            'status': 'queued',
            'payload': {
              'draft': {'text': id},
            },
          },
      ],
    };
    final client = _SurfaceRuntimeClient(
      requestHandler: (type, payload) {
        if (type == 'codex.thread.open') {
          return Future.value({
            'threadId': 'thread',
            'chatFeatures': ['codexSharedQueueV1'],
            'snapshot': {'timelineCells': <Object?>[]},
            'queue': queue(1, ['a', 'b', 'c']),
          });
        }
        if (type == 'codex.queue.get') {
          return Future.value(queue(2, ['b', 'c']));
        }
        if (type == 'codex.queue.remove') {
          return Future.error(StateError('Queue revision conflict'));
        }
        return null;
      },
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    final rendered = tester.widget<AleraMessageQueue>(
      find.byType(AleraMessageQueue),
    );
    client.emit(RuntimeHostEvent('codexQueueChanged', queue(2, ['b', 'c'])));
    await tester.pump();
    await rendered.onRemove('b');
    await tester.pump();
    final removal = client.requests.singleWhere(
      (call) => call.type == 'codex.queue.remove',
    );
    expect(removal.payload['messageId'], 'b');
    expect(removal.payload['expectedRevision'], 1);
    expect(
      tester
          .widget<AleraMessageQueue>(find.byType(AleraMessageQueue))
          .messages
          .map((row) => row.id),
      ['b', 'c'],
    );
    expect(tester.takeException(), isNull);
  });

  for (final action in ['steer', 'edit']) {
    testWidgets('queue $action keeps the rendered content revision', (
      tester,
    ) async {
      Map<String, Object?> queue(int revision) => {
        'tabId': 'codex-tab',
        'threadId': 'thread',
        'revision': revision,
        'paused': true,
        'messages': [
          {
            'id': 'message',
            'status': 'queued',
            'payload': {
              'draft': {
                'text': revision == 1 ? 'Original' : 'Changed remotely',
              },
            },
          },
        ],
      };
      final client = _SurfaceRuntimeClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') {
            return Future.value({
              'threadId': 'thread',
              'chatFeatures': ['codexSharedQueueV1'],
              'snapshot': {
                'activeTurnId': 'active',
                'timelineCells': <Object?>[],
              },
              'queue': queue(1),
            });
          }
          if (type == 'codex.queue.get') return Future.value(queue(2));
          if (type == 'codex.queue.$action') {
            return Future.error(StateError('Queue revision conflict'));
          }
          return null;
        },
      );
      addTearDown(client.dispose);
      await _pumpComposerSurface(tester, client);
      final rendered = tester.widget<AleraMessageQueue>(
        find.byType(AleraMessageQueue),
      );
      client.emit(RuntimeHostEvent('codexQueueChanged', queue(2)));
      await tester.pump();
      if (action == 'steer') {
        await rendered.onSteer('message');
      } else {
        final editing = rendered.onEdit('message');
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(field).controller!.text, 'Original');
        await tester.enterText(field, 'My correction');
        await tester.tap(find.text('Save Message'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field).controller!.text,
          'My correction',
        );
        expect(
          find.textContaining('Queue revision conflict', findRichText: true),
          findsWidgets,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await editing;
      }
      await tester.pump();
      final mutation = client.requests.singleWhere(
        (call) => call.type == 'codex.queue.$action',
      );
      expect(mutation.payload['messageId'], 'message');
      expect(mutation.payload['expectedRevision'], 1);
      if (action == 'steer') expect(mutation.payload['turnId'], 'active');
      expect(
        tester
            .widget<AleraMessageQueue>(find.byType(AleraMessageQueue))
            .messages
            .single
            .text,
        'Changed remotely',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
