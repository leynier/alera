import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  Map<String, Object?> queue(int revision) => {
    'tabId': 'tab',
    'threadId': 'thread',
    'revision': revision + 1,
    'historyRevision': revision,
    'paused': true,
    'messages': <Object?>[],
  };
  Map<String, Object?> snapshot(String id) => {
    'timelineCells': [
      {'id': id, 'kind': 'agentMessage', 'turnId': id, 'markdownText': id},
    ],
  };
  Map<String, Object?> opened(int revision) => {
    'threadId': 'thread',
    'chatFeatures': ['codexSharedQueueV1'],
    'historyRevision': revision,
    'queue': queue(revision),
    'snapshot': snapshot(revision == 0 ? 'discarded' : 'corrected'),
    'historyNextCursor': revision == 0 ? 'old-page' : 'new-page',
  };
  for (final fromEvent in [false, true]) {
    for (final failReload in [false, true]) {
      test(
        'new queue history revision reloads Mobile (event $fromEvent, failure $failReload)',
        () async {
          final reopened = Completer<Map<String, Object?>>();
          final oldPage = Completer<Map<String, Object?>>();
          var opens = 0;
          final client = FakeMobileCodexClient(
            supportsCodexGoals: false,
            requestHandler: (type, payload) {
              if (type == 'codex.thread.open') {
                opens++;
                return opens == 2
                    ? reopened.future
                    : Future.value(opened(opens == 1 ? 0 : 1));
              }
              if (type == 'codex.thread.history') return oldPage.future;
              if (type == 'codex.queue.get') return Future.value(queue(1));
              if (type == 'codex.queue.add') return Future.value(queue(1));
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
            container.dispose();
            client.dispose();
          });
          final provider = mobileCodexControllerProvider('host', 'tab');
          final listener = container.listen(provider, (_, _) {});
          addTearDown(listener.close);
          await container.read(provider.future);
          final controller = container.read(provider.notifier);
          final history = controller.loadHistory(cursor: 'old-page');
          if (fromEvent) {
            client.emit(MobileRuntimeEvent('codexQueueChanged', queue(1)));
          } else {
            await controller.refreshQueue();
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(opens, 2);
          final reload = container.read(provider.future);
          expect(
            await container.read(provider.notifier).send('While stale'),
            isFalse,
          );
          expect(
            await container.read(provider.notifier).steer('While stale'),
            isFalse,
          );
          expect(
            client.calls.where((r) => r.type == 'codex.queue.add'),
            isEmpty,
          );
          if (failReload) {
            final failure = expectLater(reload, throwsStateError);
            reopened.completeError(StateError('History unavailable'));
            await failure;
            expect(
              await container.read(provider.notifier).send('Still stale'),
              isFalse,
            );
            container.invalidate(provider);
            await container.read(provider.future);
          } else {
            reopened.complete(opened(1));
            await reload;
          }
          oldPage.complete({
            'snapshot': snapshot('discarded-page'),
            'nextCursor': 'stale',
          });
          await history;
          final current = container.read(provider).requireValue;
          expect(current.historyRevision, 1);
          expect(current.timelineCells.map((c) => c.id), ['corrected']);
          expect(current.historyNextCursor, 'new-page');
          expect(current.historyOutdated, isFalse);
          expect(
            await container.read(provider.notifier).send('After reload'),
            isTrue,
          );
          expect(
            client.calls
                .singleWhere((r) => r.type == 'codex.queue.add')
                .payload['expectedHistoryRevision'],
            1,
          );
          client.emit(MobileRuntimeEvent('codexQueueChanged', queue(1)));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(opens, failReload ? 3 : 2);
        },
      );
    }
  }
}
