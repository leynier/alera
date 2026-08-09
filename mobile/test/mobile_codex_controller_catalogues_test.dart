import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile turns carry the thread observed by the client', () async {
    final client = FakeMobileCodexClient(initialThreadId: 'thread-old');
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-thread-precondition',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-thread-precondition',
      'tab-thread-precondition',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    await container.read(provider.notifier).send('First message');
    expect(
      client.calls
          .lastWhere((call) => call.type == 'codex.turn.start')
          .payload['expectedThreadId'],
      'thread-old',
    );

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-thread-precondition',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
        'historyNextCursor': null,
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await container.read(provider.notifier).send('Second message');
    expect(
      client.calls
          .lastWhere((call) => call.type == 'codex.turn.start')
          .payload['expectedThreadId'],
      'thread-new',
    );
  });
  test(
    'mobile same-thread broadcasts preserve loaded history and switch cursors',
    () async {
      final client = FakeMobileCodexClient(
        initialThreadId: 'thread-current',
        initialSnapshot: const <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'recent',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Recent answer',
            },
          ],
        },
        responses: const <String, Map<String, Object?>>{
          'codex.thread.history': <String, Object?>{
            'snapshot': <String, Object?>{
              'timelineCells': <Object?>[
                <String, Object?>{
                  'id': 'older',
                  'kind': 'userMessage',
                  'status': 'completed',
                  'markdownText': 'Older prompt',
                },
              ],
            },
            'nextCursor': 'older-next',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-history-broadcast',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-history-broadcast',
        'tab-history-broadcast',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      await container.read(provider.notifier).loadHistory(cursor: 'older');

      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-history-broadcast',
          'threadId': 'thread-current',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'recent',
                'kind': 'assistantMessage',
                'status': 'completed',
                'markdownText': 'Updated answer',
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      var current = container.read(provider).value!;
      expect(current.timelineCells.map((cell) => cell.id), <String>[
        'older',
        'recent',
      ]);
      expect(current.timelineCells.last.markdownText, 'Updated answer');
      expect(current.historyNextCursor, 'older-next');

      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-history-broadcast',
          'threadId': 'thread-replacement',
          'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
          'historyNextCursor': null,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      current = container.read(provider).value!;
      expect(current.timelineCells, isEmpty);
      expect(current.historyNextCursor, isNull);
    },
  );
  test(
    'mobile flattens grouped skills and excludes disabled entries',
    () async {
      final client = FakeMobileCodexClient(
        responses: const <String, Map<String, Object?>>{
          'codex.skills.list': <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'cwd': '/repo',
                'skills': <Object?>[
                  <String, Object?>{
                    'name': 'enabled-skill',
                    'path': '/skills/enabled/SKILL.md',
                    'enabled': true,
                  },
                  <String, Object?>{
                    'name': 'disabled-skill',
                    'path': '/skills/disabled/SKILL.md',
                    'enabled': false,
                  },
                ],
              },
            ],
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-grouped-skills',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-grouped-skills',
        'tab-grouped-skills',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);

      final state = await container.read(provider.future);

      expect(state.skills.map((skill) => skill['name']), <String>[
        'enabled-skill',
      ]);
      expect(state.skills.single['cwd'], '/repo');
    },
  );
}
