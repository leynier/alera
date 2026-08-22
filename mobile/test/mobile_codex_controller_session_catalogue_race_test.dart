import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test(
    'session catalogue load cannot overwrite a newer account refresh',
    () async {
      final sessionSkills = Completer<Map<String, Object?>>();
      var modelRequests = 0;
      var collaborationRequests = 0;
      var skillRequests = 0;
      var appRequests = 0;
      late FakeMobileCodexClient client;
      client = FakeMobileCodexClient(
        initialThreadId: 'thread-initial',
        requestHandler: (type, payload) {
          switch (type) {
            case 'codex.thread.resume':
              return Future<Map<String, Object?>>.value(<String, Object?>{
                'threadId': 'thread-resumed',
                'snapshot': const <String, Object?>{
                  'timelineCells': <Object?>[],
                },
              });
            case 'codex.model.list':
              modelRequests += 1;
              return Future<Map<String, Object?>>.value(
                modelRequests >= 3 ? _freshModels : _staleModels,
              );
            case 'codex.collaborationModes.list':
              collaborationRequests += 1;
              return Future<Map<String, Object?>>.value(<String, Object?>{
                'data': <Object?>[
                  <String, Object?>{
                    'mode': collaborationRequests >= 3 ? 'review' : 'plan',
                  },
                ],
              });
            case 'codex.skills.list':
              skillRequests += 1;
              if (skillRequests == 2) return sessionSkills.future;
              return Future<Map<String, Object?>>.value(const <String, Object?>{
                'data': <Object?>[],
              });
            case 'codex.apps.list':
              appRequests += 1;
              return Future<Map<String, Object?>>.value(<String, Object?>{
                'data': <Object?>[
                  <String, Object?>{'id': 'app-$appRequests'},
                ],
              });
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-session-race',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-session-race',
        'tab-session-race',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);

      final resume = container
          .read(provider.notifier)
          .resumeThread(
            const MobileCodexThreadSummary(
              id: 'thread-resumed',
              title: 'Resumed',
            ),
          );
      while (skillRequests < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      client.emit(
        const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'account',
        }),
      );
      while (modelRequests < 3 || collaborationRequests < 3) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      sessionSkills.complete(const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'session-skill'},
        ],
      });
      await resume;

      final state = container.read(provider).value!;
      expect(state.models.map((model) => model.id), <String>['gpt-fresh']);
      expect(state.collaborationModes.single['mode'], 'review');
      expect(state.skills.single['name'], 'session-skill');
      expect(state.apps.single['id'], 'app-2');
    },
  );
}

const _staleModels = <String, Object?>{
  'data': <Object?>[
    <String, Object?>{'id': 'gpt-stale', 'isDefault': true},
  ],
};

const _freshModels = <String, Object?>{
  'data': <Object?>[
    <String, Object?>{'id': 'gpt-fresh', 'isDefault': true},
  ],
};
