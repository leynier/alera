import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final shared in [false, true]) {
    test(
      'mobile Stop captures the active turn without a shared pause revision: $shared',
      () async {
        final interrupt = Completer<Map<String, Object?>>();
        final client = FakeMobileCodexClient(
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
        final stopping = controller.stop();
        await Future<void>.delayed(Duration.zero);
        await controller.stop();
        final requests = client.calls
            .where((call) => call.type == 'codex.turn.interrupt')
            .toList();
        expect(requests, hasLength(1));
        expect(requests.single.payload['turnId'], 'turn');
        if (shared) {
          expect(requests.single.payload['expectedThreadId'], 'thread');
        }
        expect(
          client.calls.where((call) => call.type == 'codex.queue.pause'),
          isEmpty,
        );
        if (!shared) {
          expect(container.read(provider).value!.queuePaused, isTrue);
        }
        interrupt.complete({});
        await stopping;
      },
    );
  }
}
