import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final includeFeatures in [true, false]) {
    test(
      'missing rollout recovery preserves shared capabilities (response: $includeFeatures)',
      () async {
        const features = [
          'codexSharedQueueV1',
          'codexForkV1',
          'codexHistoryEditV1',
        ];
        final responses = <String, Map<String, Object?>>{
          'codex.thread.open': {
            'threadId': 'old',
            'chatFeatures': features,
            'historyRevision': 5,
            'snapshot': {'timelineCells': <Object?>[]},
            'recovery': {'kind': 'missingRollout'},
            'queue': {
              'threadId': 'old',
              'revision': 9,
              'historyRevision': 5,
              'paused': true,
              'messages': <Object?>[],
            },
          },
          'codex.thread.recover': {
            'threadId': 'recovered',
            if (includeFeatures) 'chatFeatures': features,
            'historyRevision': 0,
            'snapshot': {'timelineCells': <Object?>[]},
            'cwd': '/repo/new',
            'queue': {
              'threadId': 'recovered',
              'revision': 1,
              'historyRevision': 0,
              'paused': true,
              'messages': <Object?>[],
            },
          },
        };
        final client = FakeMobileCodexClient(
          requestHandler: (type, payload) => responses.containsKey(type)
              ? Future.value(responses[type]!)
              : null,
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
        await controller.recoverThread();
        final current = container.read(provider).value!;
        expect(current.supportsSharedQueue, isTrue);
        expect(current.supportsFork, isTrue);
        expect(current.supportsHistoryEdit, isTrue);
        expect(current.queueState['threadId'], 'recovered');
        expect(current.historyRevision, 0);
        expect(current.activeCwd, '/repo/new');
        expect(current.queuePaused, isTrue);
        expect(await controller.send('Continue'), isTrue);
        final submitted = client.calls.singleWhere(
          (call) => call.type == 'codex.queue.add',
        );
        expect(submitted.payload['expectedHistoryRevision'], 0);
        expect(submitted.payload['expectedThreadId'], 'recovered');
        expect(
          client.calls.where((call) => call.type == 'codex.turn.start'),
          isEmpty,
        );
      },
    );
  }
}
