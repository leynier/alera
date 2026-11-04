import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('blank ACP catalog distinguishes setup from missing installation', () {
    final provider = AgentChatProviderInstance.fromJson(<String, Object?>{
      'providerInstanceId': 'acpRegistry',
      'provider': 'acpRegistry',
      'available': false,
      'setupRequired': true,
      'installed': null,
      'unavailableReason': 'Configure an executable in Providers Settings.',
    });

    expect(provider.setupRequired, isTrue);
    expect(provider.available, isFalse);
    expect(provider.installed, isNull);
    expect(provider.auth.status, AgentChatProviderAuthStatus.unknown);
    expect(provider.setup, isEmpty);
  });

  test(
    'legacy catalogs and existing fakes default setup required to false',
    () {
      const fake = AgentChatProviderInstance(
        id: 'codex',
        provider: 'codex',
        label: 'Codex',
      );
      expect(fake.setupRequired, isFalse);

      for (final value in <Object?>[null, false, 'true', 1]) {
        final provider = AgentChatProviderInstance.fromJson(<String, Object?>{
          'providerInstanceId': 'configured-acp',
          'setupRequired': value,
          'available': false,
          'installed': false,
        });
        expect(provider.setupRequired, isFalse);
        expect(provider.installed, isFalse);
      }
      final legacy = AgentChatProviderInstance.fromJson(<String, Object?>{
        'providerInstanceId': 'codex',
      });
      expect(legacy.setupRequired, isFalse);
    },
  );

  test('Antigravity models carry their own thinking levels', () {
    final models = <Object?>[
      <String, Object?>{
        'id': 'gemini-3.8-flash',
        'label': 'Gemini 3.8 Flash',
        'source': 'discovered',
        'providerDefault': true,
        'isDefault': false,
        'reasoningEfforts': <String>['low', 'high'],
        'defaultReasoningEffort': 'high',
      },
      <String, Object?>{
        'id': 'claude-sonnet',
        'label': 'Claude Sonnet',
        'source': 'discovered',
        'providerDefault': false,
        'isDefault': false,
      },
    ].map(AgentChatModelOption.fromJson).toList();

    expect(models.first.reasoningEfforts, <String>['low', 'high']);
    expect(models.first.defaultReasoningEffort, 'high');
    expect(models.last.reasoningEfforts, isEmpty);
    expect(models.last.defaultReasoningEffort, isNull);
  });
}
