import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final failFirst in [false, true]) {
    test(
      'identical concurrent submissions have independent retry IDs ($failFirst)',
      () async {
        final gates = <Completer<Map<String, Object?>>>[];
        final ids = <Object?>[];
        final client = FakeMobileCodexClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {'timelineCells': <Object?>[]},
              });
            }
            if (type == 'codex.queue.add') {
              ids.add(payload['clientUserMessageId']);
              final gate = Completer<Map<String, Object?>>();
              gates.add(gate);
              return gate.future;
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
          container.dispose();
          client.dispose();
        });
        final provider = mobileCodexControllerProvider('host', 'tab');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await container.read(provider.future);
        final controller = container.read(provider.notifier);
        final first = controller.send('Same request');
        final second = controller.send('Same request');
        await Future<void>.delayed(Duration.zero);
        expect(ids, hasLength(2));
        expect(ids[0], isNot(ids[1]));
        final original = ids.toSet();
        for (final gate in gates.toList().reversed) {
          if (failFirst) {
            gate.completeError(TimeoutException('Acknowledgement lost'));
          } else {
            gate.complete({
              'threadId': 'thread',
              'revision': 1,
              'messages': <Object?>[],
            });
          }
        }
        expect(await first, !failFirst);
        expect(await second, !failFirst);
        if (failFirst) {
          final retryFirst = controller.send('Same request');
          final retrySecond = controller.send('Same request');
          await Future<void>.delayed(Duration.zero);
          expect(ids, hasLength(4));
          expect(ids.skip(2).toSet(), original);
          for (final gate in gates.skip(2)) {
            gate.complete({
              'threadId': 'thread',
              'revision': 1,
              'messages': <Object?>[],
            });
          }
          expect(await retryFirst, isTrue);
          expect(await retrySecond, isTrue);
        }
      },
    );
  }

  test('history edit rejects a switched conversation with matching turn identities', () async {
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) {
        if (type == 'codex.thread.open') {
          return Future.value({
            'threadId': 'original',
            'chatFeatures': ['codexSharedQueueV1', 'codexHistoryEditV1'],
            'historyRevision': 0,
            'snapshot': {'timelineCells': <Object?>[]},
          });
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
      container.dispose();
      client.dispose();
    });
    final provider = mobileCodexControllerProvider('host', 'tab');
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    final captured = controller.threadId;
    final cell = MobileCodexTimelineCell.fromJson({
      'id': 'user',
      'kind': 'userMessage',
      'turnId': 'turn',
      'itemId': 'user',
      'markdownText': 'Original',
    });
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', {
        'tabId': 'tab',
        'threadId': 'fork',
        'historyRevision': 0,
        'snapshot': {'timelineCells': <Object?>[]},
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.threadId, 'fork');
    expect(
      await controller.editUserMessage(
        cell,
        'Correction',
        expectedThreadId: captured,
        expectedHistoryRevision: 0,
      ),
      isFalse,
    );
    expect(client.calls.where((r) => r.type == 'codex.thread.edit'), isEmpty);
    expect(
      container.read(provider).value!.error,
      contains('conversation changed'),
    );
  });
}
