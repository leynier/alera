import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_failure.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_writer.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_settings_repository.dart';

void main() {
  late FakeAgentChatSettingsRepository repository;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatSettingsRepository(revision: 3);
    nextId = 0;
  });

  AgentProviderSettingsWriter writer({String? hostId}) =>
      AgentProviderSettingsWriter(
        repository: repository,
        newRequestId: () => 'request-${++nextId}',
        hostId: hostId,
      );

  test('a new instance is upserted before its secrets, each on the latest '
      'revision', () async {
    final draft =
        AgentProviderInstanceDraft.create(
          providerInstanceId: 'work-claude',
          provider: 'claudeAgent',
        ).copyWith(
          environment: const <AgentProviderEnvironmentDraft>[
            AgentProviderEnvironmentDraft(
              name: 'ANTHROPIC_API_KEY',
              sensitive: true,
            ),
          ],
        );
    final snapshot = await writer(hostId: 'build-mac').save(
      revision: 3,
      draft: draft,
      saved: null,
      secrets: const <AgentProviderPendingSecret>[
        AgentProviderPendingSecret(name: 'ANTHROPIC_API_KEY', value: 'sk-1'),
      ],
    );
    expect(repository.calls, <String>[
      'upsert work-claude @3 request-1 host=build-mac',
      'secret.set work-claude ANTHROPIC_API_KEY @4 request-2 host=build-mac',
    ]);
    expect(snapshot.revision, 5);
    // The secret value went only to the write-only verb.
    expect(
      repository.upserts.single.toJson().toString(),
      isNot(contains('sk-1')),
    );
    expect(repository.secretValues, <String>['sk-1']);
  });

  test('an unchanged draft writes only its secret changes', () async {
    final saved = AgentProviderInstanceDraft.fromEnvelope(
      AgentChatProviderInstanceEnvelope.fromJson(<String, Object?>{
        'providerInstanceId': 'codex',
        'provider': 'codex',
        'environment': <Object?>[
          <String, Object?>{
            'name': 'OPENAI_API_KEY',
            'sensitive': true,
            'secretSaved': true,
          },
        ],
      }),
    );
    await writer().save(
      revision: 3,
      draft: saved,
      saved: saved,
      secrets: const <AgentProviderPendingSecret>[
        AgentProviderPendingSecret(name: 'OPENAI_API_KEY'),
      ],
    );
    expect(repository.calls, <String>[
      'secret.clear codex OPENAI_API_KEY @3 request-1 host=local',
    ]);
  });

  test(
    'a dropped connection is retried once with the same request id',
    () async {
      repository.dropNextConnection = true;
      await writer().setEnabled(
        revision: 3,
        providerInstanceId: 'pi',
        provider: 'pi',
        enabled: false,
      );
      expect(repository.calls, <String>[
        'upsert pi @3 request-1 host=local',
        'upsert pi @3 request-1 host=local',
      ]);
      expect(repository.upserts.last.toJson(), <String, Object?>{
        'providerInstanceId': 'pi',
        'provider': 'pi',
        'enabled': false,
      });
    },
  );

  test('host errors become pane failures', () async {
    repository.nextError = const AgentChatRequestException(
      message: 'stale',
      code: 'revisionConflict',
    );
    await expectLater(
      writer().remove(revision: 1, providerInstanceId: 'work-claude'),
      throwsA(
        isA<AgentProviderSettingsFailure>().having(
          (failure) => failure.kind,
          'kind',
          AgentProviderFailureKind.revisionConflict,
        ),
      ),
    );
    repository.nextError = const AgentChatCapabilityRequired(
      AgentChatWire.providerSettingsCapability,
    );
    await expectLater(
      writer().removalImpact('work-claude'),
      throwsA(
        isA<AgentProviderSettingsFailure>().having(
          (failure) => failure.kind,
          'kind',
          AgentProviderFailureKind.updateRequired,
        ),
      ),
    );
  });

  test('removal passes the in-use confirmation through', () async {
    await writer().remove(
      revision: 3,
      providerInstanceId: 'work-claude',
      allowInUse: true,
    );
    expect(repository.calls, <String>[
      'remove work-claude @3 request-1 allowInUse=true host=local',
    ]);
  });

  test('an invalid draft never reaches the host', () async {
    final draft = AgentProviderInstanceDraft.create(
      providerInstanceId: 'bad id',
      provider: 'codex',
    );
    await expectLater(
      writer().save(revision: 3, draft: draft, saved: null),
      throwsA(isA<AgentProviderSettingsFailure>()),
    );
    expect(repository.calls, isEmpty);
  });

  group('AgentProviderPreferencesWriter', () {
    AgentProviderPreferencesWriter preferencesWriter() =>
        AgentProviderPreferencesWriter(
          repository: repository,
          newRequestId: () => 'request-${++nextId}',
          hostId: null,
        );

    test(
      'rebuilds operations from the latest preferences after a conflict',
      () async {
        repository.preferencesValue = const AgentChatPreferences(
          revision: 9,
          favorites: <AgentChatSelection>[
            AgentChatSelection(providerInstanceId: 'pi'),
          ],
        );
        repository.nextPreferencesError = const AgentChatRequestException(
          message: 'stale',
          code: 'revisionConflict',
        );
        final bases = <int>[];
        await preferencesWriter().update(
          const AgentChatPreferences(revision: 8),
          (latest) {
            bases.add(latest.revision);
            return <AgentChatPreferenceOperation>[
              AgentChatSetFavorites(<AgentChatSelection>[
                ...latest.favorites,
                const AgentChatSelection(providerInstanceId: 'codex'),
              ]),
            ];
          },
        );
        expect(bases, <int>[8, 9]);
        final sent = repository.preferenceUpdates.last.toJson();
        expect(sent['expectedRevision'], 9);
        expect(sent['requestId'], 'request-2');
        expect((sent['operations']! as List<Object?>).single, <String, Object?>{
          'type': 'setFavorites',
          'favorites': <Object?>[
            <String, Object?>{'providerInstanceId': 'pi', 'model': null},
            <String, Object?>{'providerInstanceId': 'codex', 'model': null},
          ],
        });
      },
    );
  });
}
