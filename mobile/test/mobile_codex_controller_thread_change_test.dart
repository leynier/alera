import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile replaces deferred snapshots when the thread changes', () async {
    final models = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-old',
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'old-cell',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Old',
          },
        ],
      },
      requestHandler: (type, payload) =>
          type == 'codex.model.list' ? models.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-thread-change')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-thread-change',
      'tab-thread-change',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    while (!client.calls.any((call) => call.type == 'codex.model.list')) {
      await Future.pause(.zero);
    }

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-thread-change',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'new-cell',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'New',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'new-cell',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'New',
            },
          ],
        },
      }),
    );
    models.complete(const <String, Object?>{'data': <Object?>[]});

    await container.read(provider.future);
    await Future.pause(.zero);
    await Future.pause(.zero);

    expect(
      container.read(provider).value!.timelineCells.map((cell) => cell.id),
      <String>['new-cell'],
    );
  });
}
