import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test(
    'mobile review loads workspace branches and forwards commit metadata',
    () async {
      final codex = FakeMobileCodexClient(
        responses: const <String, Map<String, Object?>>{
          'codex.review.branches': <String, Object?>{
            'branches': <String>['feature/z', 'origin/main', 'develop', 'main'],
            'currentBranch': 'develop',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-review')
              .overrideWith((ref) async => codex),
        ],
      );
      addTearDown(() {
        codex.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-review',
        'tab-review',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final branches = await controller.reviewBranches();

      expect(branches.lookupFailed, isFalse);
      expect(branches.branches, <String>['main', 'origin/main', 'feature/z']);

      await controller.review(
        target: 'commit',
        argument: ' abc123 ',
        commitTitle: ' Focused Review ',
        delivery: 'detached',
      );
      final call = codex.calls.lastWhere(
        (call) => call.type == 'codex.review.start',
      );
      expect(call.payload, <String, Object?>{
        'tabId': 'tab-review',
        'target': <String, Object?>{
          'type': 'commit',
          'sha': 'abc123',
          'title': 'Focused Review',
        },
        'delivery': 'detached',
      });
    },
  );
}
