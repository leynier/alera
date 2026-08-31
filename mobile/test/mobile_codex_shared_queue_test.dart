import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_catalog_selection.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final initialBinding in [true, false]) {
    test(
      'legacy queue ${initialBinding ? "survives first binding" : "does not move to another chat"}',
      () async {
        final firstTurn = Completer<Map<String, Object?>>();
        final client = FakeMobileCodexClient(
          initialThreadId: initialBinding ? null : 'old',
          requestHandler: (type, payload) =>
              type == 'codex.turn.start' ? firstTurn.future : null,
        );
        final container = ProviderContainer(
          overrides: [
            mobileCodexClientProvider('host')
                .overrideWith((ref) async => client),
          ],
        );
        addTearDown(() {
          client.dispose();
          container.dispose();
        });
        final provider = mobileCodexControllerProvider('host', 'tab');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await container.read(provider.future);
        final controller = container.read(provider.notifier);
        final sending = controller.send('First');
        await Future<void>.delayed(Duration.zero);
        await controller.send('Second');
        expect(container.read(provider).value!.queuedMessages, hasLength(1));
        client.emit(
          const MobileRuntimeEvent('codexThreadChanged', {
            'tabId': 'tab',
            'threadId': 'created',
            'snapshot': {'activeTurnId': 'turn', 'timelineCells': <Object?>[]},
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          container.read(provider).value!.queuedMessages,
          hasLength(initialBinding ? 1 : 0),
        );
        firstTurn.complete({
          'turn': {'id': 'turn'},
        });
        await sending;
        client.emit(
          const MobileRuntimeEvent('codexThreadChanged', {
            'tabId': 'tab',
            'threadId': 'created',
            'snapshot': {'timelineCells': <Object?>[]},
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          client.calls.where((r) => r.type == 'codex.turn.start'),
          hasLength(initialBinding ? 2 : 1),
        );
      },
    );
  }

  Map<String, Object?> queue(String thread, int revision) => {
    'tabId': 'tab',
    'threadId': thread,
    'revision': revision,
    'paused': true,
    'messages': [
      {
        'id': 'queued-$thread',
        'status': 'queued',
        'payload': {
          'draft': {'text': thread},
        },
      },
    ],
  };

  test(
    'external chat switches fetch queue and discard older fetches',
    () async {
      final oldFetch = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') {
            return Future.value({
              'threadId': 'first',
              'chatFeatures': ['codexSharedQueueV1'],
              'snapshot': {'timelineCells': <Object?>[]},
              'queue': queue('first', 9),
            });
          }
          if (type == 'codex.queue.get') {
            return payload['expectedThreadId'] == 'second'
                ? oldFetch.future
                : Future.value(queue('third', 2));
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host', 'tab');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await container.read(provider.future);
      for (final thread in ['second', 'third']) {
        client.emit(
          MobileRuntimeEvent('codexThreadChanged', {
            'tabId': 'tab',
            'threadId': thread,
            'snapshot': {'timelineCells': <Object?>[]},
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      oldFetch.complete(queue('second', 99));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        client.calls
            .where((c) => c.type == 'codex.queue.get')
            .map((c) => c.payload['expectedThreadId']),
        ['second', 'third'],
      );
      expect(
        container.read(provider).value!.queuedMessages.single['text'],
        'third',
      );
      expect(container.read(provider).value!.queuePaused, isTrue);
    },
  );

  test(
    'failed session change does not duplicate authoritative queue rows',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') {
            return Future.value({
              'threadId': 'thread',
              'chatFeatures': ['codexSharedQueueV1'],
              'snapshot': {'timelineCells': <Object?>[]},
              'queue': queue('thread', 1),
            });
          }
          if (type == 'codex.thread.new') return pending.future;
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host', 'tab');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await container.read(provider.future);
      final changing = container.read(provider.notifier).newThread();
      client.emit(MobileRuntimeEvent('codexQueueChanged', queue('thread', 2)));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      pending.completeError(StateError('New chat rejected'));
      expect(await changing, isFalse);
      expect(container.read(provider).value!.queuedMessages, hasLength(1));
      expect(container.read(provider).value!.queuePaused, isTrue);
    },
  );

  test(
    'legacy queue edit retains explicit app selection after a prefix edit',
    () async {
      final client = FakeMobileCodexClient();
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host', 'tab');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      await controller.stop();
      await controller.send(
        r'$shared',
        catalogSelections: [
          mobileCodexTrackCatalogSelection({
            'type': 'mention',
            'name': 'shared',
            'path': 'app://explicit',
          }, tokenStart: 0),
        ],
      );
      final original = container.read(provider).value!.queuedMessages.single;
      expect(
        await controller.saveQueuedMessage(original, r'  Please use $shared  '),
        isTrue,
      );
      final edited = container.read(provider).value!.queuedMessages.single;
      expect(edited['id'], original['id']);
      final selections = (edited['catalogSelections']! as List)
          .cast<Map<String, Object?>>();
      expect(
        mobileCodexActiveCatalogSelections(
          edited['text']! as String,
          selections,
        ).single['path'],
        'app://explicit',
      );
      expect(edited['text'], r'Please use $shared');
    },
  );

  test(
    'legacy Stop keeps subsequent sends queued until Resume Queue',
    () async {
      final client = FakeMobileCodexClient();
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host', 'tab');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      await controller.stop();
      await controller.send('Wait for resume');
      expect(container.read(provider).value!.queuePaused, isTrue);
      expect(container.read(provider).value!.queuedMessages, hasLength(1));
      expect(client.calls.where((r) => r.type == 'codex.turn.start'), isEmpty);
      await controller.queueAction('resume');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        client.calls.where((r) => r.type == 'codex.turn.start'),
        hasLength(1),
      );
    },
  );

  for (final steering in [false, true]) {
    test(
      'shared queue ${steering ? "Steer" : "send"} survives stale updates and a lost acknowledgement uses the same ID',
      () async {
        Map<String, Object?> queue(int revision, String text) => {
          'tabId': 'tab',
          'threadId': 'thread',
          'revision': revision,
          'paused': true,
          'messages': [
            {
              'id': 'queued',
              'status': 'queued',
              'payload': {
                'draft': {'text': text},
              },
            },
          ],
        };
        final ids = <String>[];
        final client = FakeMobileCodexClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {
                  'timelineCells': <Object?>[],
                  if (steering) 'activeTurnId': 'turn',
                },
                'queue': queue(2, 'original'),
              });
            }
            if (type == 'codex.queue.add') {
              ids.add(payload['clientUserMessageId']! as String);
              return ids.length == 1
                  ? Future.error(TimeoutException('Response lost'))
                  : Future.value(queue(4, 'newer'));
            }
            return null;
          },
        );
        final container = ProviderContainer(
          overrides: [
            mobileCodexClientProvider('host')
                .overrideWith((ref) async => client),
          ],
        );
        addTearDown(() {
          client.dispose();
          container.dispose();
        });
        final provider = mobileCodexControllerProvider('host', 'tab');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await container.read(provider.future);
        client.emit(MobileRuntimeEvent('codexQueueChanged', queue(3, 'newer')));
        client.emit(MobileRuntimeEvent('codexQueueChanged', queue(1, 'stale')));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          container.read(provider).value!.queuedMessages.single['text'],
          'newer',
        );
        expect(
          client.calls.where((call) => call.type == 'codex.turn.start'),
          isEmpty,
        );
        final controller = container.read(provider.notifier);
        expect(
          await (steering
              ? controller.steer('Do this once')
              : controller.send('Do this once')),
          isFalse,
        );
        expect(
          await (steering
              ? controller.steer('Do this once')
              : controller.send('Do this once')),
          isTrue,
        );
        expect(ids[0], ids[1]);
      },
    );
  }
}
