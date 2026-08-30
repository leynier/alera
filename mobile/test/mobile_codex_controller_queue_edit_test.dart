import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test(
    'editing a queued message drops catalog selections removed from text',
    () async {
      final client = FakeMobileCodexClient(
        initialSnapshot: const <String, Object?>{'activeTurnId': 'turn-active'},
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-queue-catalog')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-queue-catalog',
        'tab-queue-catalog',
      );
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      await controller.send(
        r'$review inspect this',
        catalogSelections: const <Map<String, Object?>>[
          <String, Object?>{
            'type': 'skill',
            'name': 'review',
            'path': '/skills/review',
          },
        ],
      );
      controller.editQueuedMessage(0, 'Inspect this without a skill');

      expect(
        container
            .read(provider)
            .value!
            .queuedMessages
            .single['catalogSelections'],
        isEmpty,
      );
    },
  );
}
