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
      expect(local.claudeDefaultShowInUsage, isTrue);
      expect(local.selectedClaudeProfile, 'default');
      expect(local.environment.kimiApiKey, 'KIMI_API_KEY');
      expect(local.unpinnedQuotaKeys, isEmpty);
      for (final provider in AgentQuotaProviderId.values) {
        expect(local.isQuotaPinned(provider), isTrue);
      }
    });

    test('derives stable pin keys per provider and claude account', () {
      expect(AgentQuotaHostSettings.quotaPinKey(.codex), 'codex');
      expect(AgentQuotaHostSettings.quotaPinKey(.claude), 'claude:default');
      expect(
        AgentQuotaHostSettings.quotaPinKey(
          .claude,
          claudeAccountId: 'leynierdev',
        ),
        'claude:leynierdev',
      );
    });

    test('parses unpinned quota keys with absence meaning pinned', () {
      final host = AgentQuotaHostSettings.fromJson(<String, Object?>{
        'unpinnedQuotaKeys': <String>['codex', 'claude:leynierdev'],
      });

      expect(host.isQuotaPinned(.codex), isFalse);
      expect(
        host.isQuotaPinned(.claude, claudeAccountId: 'leynierdev'),
        isFalse,
      );
      expect(host.isQuotaPinned(.claude), isTrue);
      expect(host.isQuotaPinned(.kimi), isTrue);
    });

    test('parses host-specific quota configuration', () {
      final quotas = AgentQuotaSettings.fromJson(<String, Object?>{
        'hosts': <String, Object?>{
          'remote': <String, Object?>{
            'enabledProviders': <String>['claude', 'grok', 'zai'],
            'claudeDefaultEnabled': false,
            'claudeDefaultShowInUsage': false,
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
      expect(remote.claudeProfiles.single.showInUsage, isTrue);
      expect(remote.claudeProfiles.single.usageLabel, 'ccdev');
      expect(remote.claudeDefaultEnabled, isFalse);
      expect(remote.claudeDefaultShowInUsage, isFalse);
      expect(remote.selectedClaudeProfile, 'leynierdev');
      expect(remote.environment.kimiApiKey, 'REMOTE_KIMI_KEY');
    });

    test('parses profile, environment, and host settings directly', () {
      final profile = ClaudeQuotaProfileSettings.fromJson(<String, Object?>{
        'alias': 'cc41',
        'profile': 'leynier41',
        'showInUsage': false,
        'usageDisplayName': 'Personal',
      });
      final environment = AgentQuotaEnvironmentSettings.fromJson(
        <String, Object?>{'kimiApiKey': 'CUSTOM_KIMI_KEY'},
      );
      final host = AgentQuotaHostSettings.fromJson(<String, Object?>{
        'claudeProfiles': <Object?>[profile.toMap()],
        'environment': environment.toMap(),
      });

      expect(host.claudeProfiles.single.alias, 'cc41');
      expect(host.claudeProfiles.single.showInUsage, isFalse);
      expect(host.claudeProfiles.single.usageLabel, 'Personal');
      expect(host.environment.kimiApiKey, 'CUSTOM_KIMI_KEY');
    });
  });
}
