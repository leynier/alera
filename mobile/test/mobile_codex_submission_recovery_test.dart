import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final steer in [false, true]) {
    test(
      'lost ${steer ? "Steer" : "send"} acknowledgement survives controller disposal',
      () async {
        var thread = 'thread';
        final ids = <Object?>[];
        final client = FakeMobileCodexClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': thread,
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {
                  'activeTurnId': 'turn',
                  'timelineCells': <Object?>[],
                },
              });
            }
            if (type == 'codex.queue.add') {
              ids.add(payload['clientUserMessageId']);
              return Future.error(StateError('Acknowledgement lost'));
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
        final provider = mobileCodexControllerProvider('host', 'retry');
        for (var attempt = 0; attempt < 3; attempt++) {
          if (attempt == 2) thread = 'different';
          final listener = container.listen(provider, (_, _) {});
          await container.read(provider.future);
          final controller = container.read(provider.notifier);
          expect(
            await (steer
                ? controller.steer('Correction')
                : controller.send('Correction')),
            isFalse,
          );
          listener.close();
          await container.pump();
          expect(container.exists(provider), isFalse);
        }
        expect(ids, hasLength(3));
        expect(ids[1], ids[0]);
        expect(ids[2], isNot(ids[0]));
      },
    );
  }
}
