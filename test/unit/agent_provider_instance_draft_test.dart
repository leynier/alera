import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_writer.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_entries.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AgentChatProviderInstanceEnvelope envelope() =>
      AgentChatProviderInstanceEnvelope.fromJson(<String, Object?>{
        'providerInstanceId': 'work-cursor',
        'provider': 'cursor',
        'label': 'Work Cursor',
        'enabled': true,
        'executable': '/opt/cursor/agent',
        'args': <String>['--profile', 'Work Laptop'],
        'environment': <Object?>[
          <String, Object?>{'name': 'CURSOR_REGION', 'value': 'eu'},
          <String, Object?>{
            'name': 'CURSOR_API_KEY',
            'sensitive': true,
            'value': 'leaked-by-a-bad-host',
            'secretSaved': true,
          },
        ],
        'options': <String, Object?>{
          'bridgeUrl': 'http://127.0.0.1:7000',
          'apiKey': 'leaked-by-a-bad-host',
        },
        'sensitiveOptions': <String>['apiKey'],
        'secretOptions': <Object?>[
          <String, Object?>{'name': 'apiKey', 'secretSaved': true},
        ],
        'customModels': <String>['gpt-5.6-sol'],
        'defaultModel': 'gpt-5.6-sol',
        'revision': 4,
      });

  group('AgentProviderInstanceDraft', () {
    test('seeds from the envelope without any sensitive value', () {
      final draft = AgentProviderInstanceDraft.fromEnvelope(envelope());
      expect(draft.hasOverride, isTrue);
      expect(draft.label, 'Work Cursor');
      final secret = draft.environment.singleWhere(
        (entry) => entry.name == 'CURSOR_API_KEY',
      );
      expect(secret.sensitive, isTrue);
      expect(secret.value, isEmpty);
      expect(secret.secretSaved, isTrue);
      expect(draft.options.containsKey('apiKey'), isFalse);
      expect(draft.optionSecretSaved('apiKey'), isTrue);
    });

    test('the upsert payload never carries a secret value', () {
      final draft = AgentProviderInstanceDraft.fromEnvelope(envelope())
          .copyWith(label: 'Cursor (Work)');
      final json = draft.toEdit().toJson();
      final encoded = json.toString();
      expect(encoded, isNot(contains('leaked-by-a-bad-host')));
      final environment = json['environment']! as List<Object?>;
      expect(
        environment,
        contains(
          equals(<String, Object?>{
            'name': 'CURSOR_API_KEY',
            'sensitive': true,
          }),
        ),
      );
      // Every secret option the provider accepts is declared, so a value can
      // be set right after the first save.
      expect(
        json['sensitiveOptions'],
        containsAll(<String>['apiKey', 'bearerToken', 'bridgeBearerToken']),
      );
      expect(json['args'], <String>['--profile', 'Work Laptop']);
      expect(json['defaultModel'], 'gpt-5.6-sol');
    });

    test('clearing the default model is an explicit reset', () {
      final draft = AgentProviderInstanceDraft.fromEnvelope(envelope())
          .copyWith(resetDefaultModel: true);
      final json = draft.toEdit().toJson();
      expect(json.containsKey('defaultModel'), isTrue);
      expect(json['defaultModel'], isNull);
    });

    test('dirty tracking compares persisted fields only', () {
      final seeded = AgentProviderInstanceDraft.fromEnvelope(envelope());
      final again = AgentProviderInstanceDraft.fromEnvelope(envelope());
      expect(seeded.signature, again.signature);
      expect(
        seeded.copyWith(executable: '/usr/bin/agent').signature,
        isNot(seeded.signature),
      );
      // Whitespace around a label is not an edit.
      expect(
        seeded.copyWith(label: '  Work Cursor ').signature,
        seeded.signature,
      );
    });

    test('validation names the first problem in field order', () {
      final draft =
          AgentProviderInstanceDraft.create(
            providerInstanceId: '2fast',
            provider: 'codex',
          ).copyWith(
            environment: const <AgentProviderEnvironmentDraft>[
              AgentProviderEnvironmentDraft(name: 'OK_NAME'),
              AgentProviderEnvironmentDraft(name: 'OK_NAME'),
              AgentProviderEnvironmentDraft(name: 'bad-name'),
            ],
          );
      final problems = draft.validate();
      expect(problems.first, startsWith('Instance ids use letters'));
      expect(problems, contains('OK_NAME is listed more than once.'));
      expect(
        problems,
        contains('bad-name is not a valid environment variable name.'),
      );
    });

    test('a secret name is accepted only once the host declares it', () {
      final stored = AgentProviderInstanceDraft.fromEnvelope(envelope());
      expect(stored.acceptsSecret('CURSOR_API_KEY'), isTrue);
      expect(stored.acceptsSecret('CURSOR_REGION'), isFalse);
      expect(stored.acceptsSecret('option:apiKey'), isTrue);
      expect(stored.acceptsSecret('option:bearerToken'), isFalse);
      final fresh = AgentProviderInstanceDraft.create(
        providerInstanceId: 'cursor-2',
        provider: 'cursor',
      );
      expect(fresh.acceptsSecret('option:apiKey'), isFalse);
    });
  });

  test('pending secrets for removed variables are dropped', () {
    final draft = AgentProviderInstanceDraft.fromEnvelope(envelope()).copyWith(
      environment: const <AgentProviderEnvironmentDraft>[
        AgentProviderEnvironmentDraft(name: 'CURSOR_REGION', value: 'eu'),
      ],
    );
    final writable = agentProviderWritableSecrets(
      draft,
      const <AgentProviderPendingSecret>[
        AgentProviderPendingSecret(name: 'CURSOR_API_KEY', value: 'x'),
        AgentProviderPendingSecret(name: 'option:apiKey', value: 'y'),
        AgentProviderPendingSecret(name: 'option:serverPassword', value: 'z'),
      ],
    );
    expect(writable.map((secret) => secret.name), <String>['option:apiKey']);
  });

  group('arguments', () {
    test('split keeps quoted runs and join quotes them back', () {
      final args = agentProviderSplitArguments(
        '--profile "Work Laptop" --flag \'a b\'  plain',
      );
      expect(args, <String>[
        '--profile',
        'Work Laptop',
        '--flag',
        'a b',
        'plain',
      ]);
      expect(
        agentProviderSplitArguments(agentProviderJoinArguments(args)),
        args,
      );
      expect(agentProviderSplitArguments('   '), isEmpty);
    });
  });

  group('agentProviderEntries', () {
    test('merges catalog, stored-only and unsaved instances in order', () {
      final snapshot = AgentChatProviderSettingsSnapshot(
        revision: 7,
        instances: <AgentChatProviderInstanceEnvelope>[
          envelope(),
          const AgentChatProviderInstanceEnvelope(
            providerInstanceId: 'codex',
            provider: 'codex',
            enabled: false,
          ),
        ],
      );
      final entries = agentProviderEntries(
        catalog: const <AgentChatProviderInstance>[
          AgentChatProviderInstance(
            id: 'codex',
            provider: 'codex',
            label: 'Codex',
          ),
          AgentChatProviderInstance(
            id: 'claudeAgent',
            provider: 'claudeAgent',
            label: 'Claude',
          ),
        ],
        snapshot: snapshot,
        unsavedNew: AgentProviderInstanceDraft.create(
          providerInstanceId: 'pi-2',
          provider: 'pi',
        ),
      );
      expect(entries.map((entry) => entry.id), <String>[
        'codex',
        'claudeAgent',
        'work-cursor',
        'pi-2',
      ]);
      // The stored row wins for enabled state and label.
      expect(entries[0].enabled, isFalse);
      expect(entries[2].label, 'Work Cursor');
      expect(entries[2].catalog, isNull);
      expect(entries[3].unsaved, isTrue);
      expect(entries[3].label, 'Pi');
      // A catalog-only instance seeds defaults with no override row.
      expect(entries[1].seed().hasOverride, isFalse);
      expect(entries[2].seed().hasOverride, isTrue);
    });
  });
}
