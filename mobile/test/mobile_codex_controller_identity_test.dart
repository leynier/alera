import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test(
    'mobile reconciles remapped progress cells by semantic identity',
    () async {
      final client = FakeMobileCodexClient(
        initialThreadId: 'thread-current',
        initialSnapshot: const <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'item-live-progress',
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'inProgress',
              'isStreaming': true,
              'markdownText': 'Inspecting',
              'metadata': <String, Object?>{'streamPhase': 'commentary'},
            },
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-progress-identity',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-progress-identity',
        'tab-progress-identity',
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
          'tabId': 'tab-progress-identity',
          'threadId': 'thread-current',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'item-rollout-progress',
                'turnId': 'turn-1',
                'kind': 'progressText',
                'status': 'completed',
                'markdownText': 'Inspecting files',
                'metadata': <String, Object?>{'streamPhase': 'commentary'},
              },
            ],
          },
          'snapshotDelta': <String, Object?>{
            'timelineUpserts': <Object?>[
              <String, Object?>{
                'id': 'item-rollout-progress',
                'turnId': 'turn-1',
                'kind': 'progressText',
                'status': 'completed',
                'markdownText': 'Inspecting files',
                'metadata': <String, Object?>{'streamPhase': 'commentary'},
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);

      final progress = container
          .read(provider)
          .value!
          .timelineCells
          .where((cell) => cell.kind == 'progressText')
          .toList();
      expect(progress, hasLength(1));
      expect(progress.single.id, 'item-rollout-progress');
      expect(progress.single.markdownText, 'Inspecting files');
    },
  );

  test('mobile keeps repeated same-text user messages distinct', () async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'user-client-1',
            'turnId': 'turn-1',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Continue',
            'metadata': <String, Object?>{
              'clientUserMessageId': 'client-1',
              'isSteering': true,
            },
          },
        ],
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-repeated-user-message',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-repeated-user-message',
      'tab-repeated-user-message',
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
        'tabId': 'tab-repeated-user-message',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'user-client-2',
              'turnId': 'turn-1',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Continue',
              'metadata': <String, Object?>{
                'clientUserMessageId': 'client-2',
                'isSteering': true,
              },
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'user-client-2',
              'turnId': 'turn-1',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Continue',
              'metadata': <String, Object?>{
                'clientUserMessageId': 'client-2',
                'isSteering': true,
              },
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);

    final userIds = container
        .read(provider)
        .value!
        .timelineCells
        .where((cell) => cell.kind == 'userMessage')
        .map((cell) => cell.id)
        .toSet();
    expect(userIds, <String>{'user-client-1', 'user-client-2'});
  });

  test('mobile preserves a repeated agent cell during one remap', () async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: <String, Object?>{
        'timelineCells': <Object?>[
          for (final id in <String>['item-agent-1', 'item-agent-2'])
            <String, Object?>{
              'id': id,
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
        mobileCodexClientProvider(
          'host-repeated-agent',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-repeated-agent',
      'tab-repeated-agent',
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
        'tabId': 'tab-repeated-agent',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'item-agent-remapped',
              'turnId': 'turn-1',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Done',
              'metadata': <String, Object?>{'streamPhase': 'final_answer'},
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'item-agent-remapped',
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

    final agentIds = container
        .read(provider)
        .value!
        .timelineCells
        .where((cell) => cell.kind == 'assistantMessage')
        .map((cell) => cell.id)
        .toSet();
    expect(agentIds, <String>{'item-agent-2', 'item-agent-remapped'});
  });

  test('mobile matches a legacy phase to one modern phase', () async {
    final commentary = await _mobilePhaseReconciliation(
      kind: 'progressText',
      modernPhase: 'commentary',
    );
    expect(commentary, hasLength(1));
    expect(commentary.single.id, 'modern');

    final finalAnswer = await _mobilePhaseReconciliation(
      kind: 'assistantMessage',
      modernPhase: 'final_answer',
    );
    expect(finalAnswer, hasLength(1));
    expect(finalAnswer.single.id, 'modern');
  });

  test('mobile keeps two explicit stream phases distinct', () async {
    final cells = await _mobilePhaseReconciliation(
      kind: 'assistantMessage',
      legacyPhase: 'commentary',
      modernPhase: 'final_answer',
    );
    expect(cells.map((cell) => cell.id), <String>['legacy', 'modern']);
  });

  test(
    'mobile preserves ambiguous explicit phases for phase-less history',
    () async {
      final cells = await _mobilePhaseReconciliation(
        kind: 'assistantMessage',
        legacyPhases: const <String?>['commentary', 'final_answer'],
        modernPhase: null,
      );
      expect(cells.map((cell) => cell.id), <String>[
        'legacy-0',
        'legacy-1',
        'modern',
      ]);
    },
  );

  test('mobile preserves ambiguous streaming prefix candidates', () async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: <String, Object?>{
        'timelineCells': <Object?>[
          for (final entry in <(String, String)>[
            ('short', 'Inspecting'),
            ('long', 'Inspecting files'),
          ])
            <String, Object?>{
              'id': entry.$1,
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'inProgress',
              'isStreaming': true,
              'markdownText': entry.$2,
              'metadata': <String, Object?>{'streamPhase': 'commentary'},
            },
        ],
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-ambiguous-prefix',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-ambiguous-prefix',
      'tab-ambiguous-prefix',
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
        'tabId': 'tab-ambiguous-prefix',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'modern',
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'completed',
              'markdownText': 'Inspecting files now',
              'metadata': <String, Object?>{'streamPhase': 'commentary'},
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(provider).value!.timelineCells.map((cell) => cell.id),
      <String>['short', 'long', 'modern'],
    );
  });
}

Future<List<MobileCodexTimelineCell>> _mobilePhaseReconciliation({
  required String kind,
  String? legacyPhase,
  List<String?>? legacyPhases,
  required String? modernPhase,
}) async {
  final initialPhases = legacyPhases ?? <String?>[legacyPhase];
  final client = FakeMobileCodexClient(
    initialThreadId: 'thread-current',
    initialSnapshot: <String, Object?>{
      'timelineCells': <Object?>[
        for (var index = 0; index < initialPhases.length; index += 1)
          <String, Object?>{
            'id': initialPhases.length == 1 ? 'legacy' : 'legacy-$index',
            'turnId': 'turn-1',
            'kind': kind,
            'status': 'completed',
            'markdownText': 'Same response',
            'metadata': <String, Object?>{'streamPhase': ?initialPhases[index]},
          },
      ],
    },
  );
  final container = ProviderContainer(
    overrides: [
      mobileCodexClientProvider(
        'host-phase-$kind-$modernPhase',
      ).overrideWith((ref) async => client),
    ],
  );
  final provider = mobileCodexControllerProvider(
    'host-phase-$kind-$modernPhase',
    'tab-phase',
  );
  final listener = container.listen(provider, (_, _) {}, fireImmediately: true);
  try {
    await container.read(provider.future);
    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-phase',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'modern',
              'turnId': 'turn-1',
              'kind': kind,
              'status': 'completed',
              'markdownText': 'Same response',
              'metadata': <String, Object?>{'streamPhase': ?modernPhase},
            },
          ],
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);
    return container.read(provider).value!.timelineCells;
  } finally {
    listener.close();
    container.dispose();
    client.dispose();
  }
}
