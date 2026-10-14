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
}
