import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('an exact mobile replacement preserves repeated agent text', () async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'item-exact',
            'turnId': 'turn-1',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Done',
            'metadata': <String, Object?>{'streamPhase': 'final_answer'},
          },
          <String, Object?>{
            'id': 'item-duplicate',
            'turnId': 'turn-1',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Done',
            'metadata': <String, Object?>{'streamPhase': 'final_answer'},
          },
        ],
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-exact-identity')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-exact-identity',
      'tab-exact-identity',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-exact-identity',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'item-exact',
              'turnId': 'turn-1',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Done',
              'metadata': <String, Object?>{'streamPhase': 'final_answer'},
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container
          .read(provider)
          .value!
          .timelineCells
          .where((cell) => cell.kind == 'assistantMessage')
          .map((cell) => cell.id),
      <String>['item-duplicate', 'item-exact'],
    );
  });
}
