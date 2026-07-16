import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentQuotaSettings', () {
    test('uses conservative local defaults', () {
      const quotas = AgentQuotaSettings.defaults;
      final local = quotas.forHost('local');

      expect(local.enabledProviders, AgentQuotaProviderId.values);
      expect(local.claudeProfiles, isEmpty);
      expect(local.claudeDefaultEnabled, isTrue);
      expect(local.selectedClaudeProfile, 'default');
      expect(local.environment.kimiApiKey, 'KIMI_APY_KEY');
    });

    test('parses host-specific quota configuration', () {
      final quotas = AgentQuotaSettings.fromJson(<String, Object?>{
        'hosts': <String, Object?>{
          'remote': <String, Object?>{
            'enabledProviders': <String>['claude', 'grok', 'zai'],
            'claudeDefaultEnabled': false,
            'claudeProfiles': <Object?>[
              <String, Object?>{'alias': 'ccdev', 'profile': 'leynierdev'},
            ],
            'selectedClaudeProfile': 'leynierdev',
            'environment': <String, Object?>{'kimiApiKey': 'REMOTE_KIMI_KEY'},
          },
        },
      });
      final remote = quotas.forHost('remote');

      expect(remote.enabledProviders, <AgentQuotaProviderId>[
        AgentQuotaProviderId.claude,
        AgentQuotaProviderId.grok,
        AgentQuotaProviderId.zai,
      ]);
      expect(remote.claudeProfiles.single.alias, 'ccdev');
      expect(remote.claudeDefaultEnabled, isFalse);
      expect(remote.selectedClaudeProfile, 'leynierdev');
      expect(remote.environment.kimiApiKey, 'REMOTE_KIMI_KEY');
    });

    test('parses profile, environment, and host settings directly', () {
      final profile = ClaudeQuotaProfileSettings.fromJson(<String, Object?>{
        'alias': 'cc41',
        'profile': 'leynier41',
      });
      final environment = AgentQuotaEnvironmentSettings.fromJson(
        <String, Object?>{'kimiApiKey': 'CUSTOM_KIMI_KEY'},
      );
      final host = AgentQuotaHostSettings.fromJson(<String, Object?>{
        'claudeProfiles': <Object?>[profile.toMap()],
        'environment': environment.toMap(),
      });

      expect(host.claudeProfiles.single.alias, 'cc41');
      expect(host.environment.kimiApiKey, 'CUSTOM_KIMI_KEY');
    });
  });
}
