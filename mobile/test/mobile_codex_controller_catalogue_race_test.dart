import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_preferences_repository.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('account refresh in the build publication gap is replayed', () async {
    var modelRequests = 0;
    var scheduledRefresh = false;
    late FakeMobileCodexClient client;
    client = FakeMobileCodexClient(
      requestHandler: (type, payload) {
        if (type == 'codex.model.list') {
          modelRequests += 1;
          return Future<Map<String, Object?>>.value(
            modelRequests == 1 ? _modelsPayload : _freshModelsPayload,
          );
        }
        if (type == 'codex.apps.list' && !scheduledRefresh) {
          scheduledRefresh = true;
          scheduleMicrotask(() {
            client.emit(
              const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
                'catalog': 'account',
              }),
            );
          });
        }
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-publish',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-publish',
      'tab-publish',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);

    await container.read(provider.future);
    await _settleCatalogueRefresh();

    final state = container.read(provider).value!;
    expect(modelRequests, 2);
    expect(state.models.map((model) => model.id), <String>['gpt-fresh']);
  });

  test('account refresh is replayed after a dependency rebuild', () async {
    var modelRequests = 0;
    var appRequests = 0;
    late FakeMobileCodexClient client;
    client = FakeMobileCodexClient(
      requestHandler: (type, payload) {
        if (type == 'codex.model.list') {
          modelRequests += 1;
          return Future<Map<String, Object?>>.value(
            modelRequests < 3 ? _modelsPayload : _freshModelsPayload,
          );
        }
        if (type == 'codex.apps.list') {
          appRequests += 1;
          if (appRequests == 2) {
            scheduleMicrotask(() {
              client.emit(
                const MobileRuntimeEvent(
                  'codexCatalogChanged',
                  <String, Object?>{'catalog': 'account'},
                ),
              );
            });
          }
        }
        return null;
      },
    );
    final clientProvider = mobileCodexClientProvider('host-rebuild');
    final container = ProviderContainer(
      overrides: [clientProvider.overrideWith((ref) async => client)],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-rebuild',
      'tab-rebuild',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);

    await container.read(provider.future);
    container.invalidate(clientProvider);
    await container.read(provider.future);
    await _settleCatalogueRefresh();

    final state = container.read(provider).value!;
    expect(appRequests, 2);
    expect(modelRequests, 3);
    expect(state.models.map((model) => model.id), <String>['gpt-fresh']);
  });

  test(
    'account refresh queued during build reloads stale catalogues',
    () async {
      final initialModels = Completer<Map<String, Object?>>();
      var modelRequests = 0;
      final client = FakeMobileCodexClient(
        configuration: const <String, Object?>{},
        requestHandler: (type, payload) {
          if (type != 'codex.model.list') return null;
          modelRequests += 1;
          if (modelRequests == 1) return initialModels.future;
          return Future<Map<String, Object?>>.value(_freshModelsPayload);
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-build',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host-build', 'tab-build');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      while (modelRequests == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      client.emit(
        const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'account',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      initialModels.complete(_modelsPayload);

      final state = await container.read(provider.future);
      expect(modelRequests, 2);
      expect(state.models.map((model) => model.id), <String>['gpt-fresh']);
    },
  );

  test(
    'account refresh during tab configure is drained before publish',
    () async {
      final initialConfigure = Completer<Map<String, Object?>>();
      var modelRequests = 0;
      var configureRequests = 0;
      final client = FakeMobileCodexClient(
        responses: <String, Map<String, Object?>>{
          'codex.model.list': _modelsPayload,
        },
        requestHandler: (type, payload) {
          if (type == 'codex.model.list') {
            modelRequests += 1;
            if (modelRequests > 1) {
              return Future<Map<String, Object?>>.value(
                _freshModelsWithPreferredPayload,
              );
            }
            return null;
          }
          if (type == 'codex.tab.configure') {
            configureRequests += 1;
            return initialConfigure.future;
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-configure',
          ).overrideWith((ref) async => client),
          mobileCodexPreferencesRepositoryProvider.overrideWithValue(
            const _TestPreferencesRepository(),
          ),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-configure',
        'tab-configure',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      while (configureRequests == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      client.emit(
        const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'account',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      initialConfigure.complete(const <String, Object?>{});

      final state = await container.read(provider.future);
      expect(modelRequests, 2);
      expect(configureRequests, 1);
      expect(state.models.map((model) => model.id), <String>[
        'gpt-fresh',
        'gpt-alternate',
      ]);
      expect(state.selectedModel, 'gpt-alternate');
    },
  );

  test('account refresh preserves options changed while models load', () async {
    final modelRefresh = Completer<Map<String, Object?>>();
    var refreshAccount = false;
    final client = FakeMobileCodexClient(
      responses: <String, Map<String, Object?>>{
        'codex.model.list': _modelsPayload,
      },
      requestHandler: (type, payload) {
        if (!refreshAccount) return null;
        if (type == 'codex.model.list') return modelRefresh.future;
        if (type == 'codex.collaborationModes.list') {
          return Future<Map<String, Object?>>.value(const <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'mode': 'review'},
            ],
          });
        }
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider('host-1', 'tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    refreshAccount = true;
    client.emit(
      const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(provider.notifier);
    controller.setModel('gpt-alternate');
    controller.setReasoning('high');
    controller.setSpeed('fast');
    controller.setCollaborationMode('plan');
    modelRefresh.complete(_modelsPayload);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.selectedModel, 'gpt-alternate');
    expect(state.reasoningEffort, 'high');
    expect(state.speedMode, 'fast');
    expect(state.collaborationMode, 'plan');
    expect(state.collaborationModes.single['mode'], 'review');
  });

  test('account refresh preserves models when model discovery fails', () async {
    var refreshAccount = false;
    final client = FakeMobileCodexClient(
      responses: <String, Map<String, Object?>>{
        'codex.model.list': _modelsPayload,
      },
      requestHandler: (type, payload) {
        if (!refreshAccount) return null;
        if (type == 'codex.model.list') {
          return Future<Map<String, Object?>>.error(
            StateError('model refresh failed'),
          );
        }
        if (type == 'codex.collaborationModes.list') {
          return Future<Map<String, Object?>>.value(const <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'mode': 'review'},
            ],
          });
        }
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-model-failure',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-model-failure',
      'tab-model-failure',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    refreshAccount = true;
    client.emit(
      const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await _settleCatalogueRefresh();

    final state = container.read(provider).value!;
    expect(state.models.map((model) => model.id), <String>[
      'gpt-current',
      'gpt-alternate',
    ]);
    expect(state.collaborationModes.single['mode'], 'review');
  });

  test(
    'account refresh preserves collaboration modes when discovery fails',
    () async {
      var refreshAccount = false;
      final client = FakeMobileCodexClient(
        responses: <String, Map<String, Object?>>{
          'codex.model.list': _modelsPayload,
        },
        requestHandler: (type, payload) {
          if (!refreshAccount) return null;
          if (type == 'codex.model.list') {
            return Future<Map<String, Object?>>.value(_freshModelsPayload);
          }
          if (type == 'codex.collaborationModes.list') {
            return Future<Map<String, Object?>>.error(
              StateError('mode refresh failed'),
            );
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-mode-failure',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-mode-failure',
        'tab-mode-failure',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      final initial = await container.read(provider.future);
      expect(initial.collaborationModes.single['mode'], 'plan');

      refreshAccount = true;
      client.emit(
        const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'account',
        }),
      );
      await _settleCatalogueRefresh();

      final state = container.read(provider).value!;
      expect(state.models.map((model) => model.id), <String>['gpt-fresh']);
      expect(state.collaborationModes.single['mode'], 'plan');
    },
  );
}

final class _TestPreferencesRepository
    implements MobileCodexPreferencesRepository {
  const _TestPreferencesRepository();

  @override
  Future<MobileCodexPreferences> load(String hostId) async =>
      const MobileCodexPreferences(model: 'gpt-alternate');

  @override
  Future<void> save(String hostId, MobileCodexPreferences preferences) async {}
}

Future<void> _settleCatalogueRefresh() async {
  for (var index = 0; index < 4; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _modelsPayload = <String, Object?>{
  'data': <Object?>[
    <String, Object?>{
      'id': 'gpt-current',
      'displayName': 'Current',
      'isDefault': true,
    },
    <String, Object?>{
      'id': 'gpt-alternate',
      'displayName': 'Alternate',
      'supportedReasoningEfforts': <Object?>[
        <String, Object?>{'reasoningEffort': 'high'},
      ],
      'additionalSpeedTiers': <String>['fast'],
    },
  ],
};

const _freshModelsPayload = <String, Object?>{
  'data': <Object?>[
    <String, Object?>{
      'id': 'gpt-fresh',
      'displayName': 'Fresh',
      'isDefault': true,
    },
  ],
};

const _freshModelsWithPreferredPayload = <String, Object?>{
  'data': <Object?>[
    <String, Object?>{
      'id': 'gpt-fresh',
      'displayName': 'Fresh',
      'isDefault': true,
    },
    <String, Object?>{
      'id': 'gpt-alternate',
      'displayName': 'Alternate',
      'supportedReasoningEfforts': <Object?>[
        <String, Object?>{'reasoningEffort': 'medium'},
      ],
    },
  ],
};
