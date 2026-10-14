import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_hosts.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_providers.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_dialogs.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_section.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_resource_sections.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Providers is a Resources section reachable by search', () {
    final sections = settingsResourceSections(
      paneKeys: (_, _) => <String, GlobalKey>{},
    );
    final providers = sections.singleWhere(
      (section) => section.id == agentProviderSettingsSectionId,
    );
    expect(providers.title, 'Providers');
    expect(providers.navGroup, SettingsNavGroup.resources);
    expect(providers.description, contains('For terminal tabs, use Agent'));
    for (final query in <String>['api key', 'custom model', 'sign in']) {
      expect(providers.matches(query), isTrue, reason: query);
    }
  });

  group('agentProviderInitialHost', () {
    const options = <AgentProviderHostOption>[
      AgentProviderHostOption(hostId: null, label: 'This Device'),
      AgentProviderHostOption(hostId: 'build-mac', label: 'Build Mac'),
    ];

    test(
      'opens on a listed requested host, else the active workspace host',
      () {
        expect(
          agentProviderInitialHost(
            options: options,
            requestedHostId: 'build-mac',
          ),
          'build-mac',
        );
        expect(
          agentProviderInitialHost(
            options: options,
            requestedHostId: 'gone',
            activeWorkspaceHostId: 'build-mac',
          ),
          'build-mac',
        );
        expect(
          agentProviderInitialHost(
            options: options,
            requestedHostId: 'local',
            activeWorkspaceHostId: 'gone',
          ),
          isNull,
        );
      },
    );
  });

  test('a settings event without a host reaches every host view', () {
    expect(agentProviderEventConcerns(null, 'build-mac'), isTrue);
    expect(agentProviderEventConcerns('build-mac', 'build-mac'), isTrue);
    expect(agentProviderEventConcerns('build-mac', null), isFalse);
    expect(agentProviderEventConcerns('local', null), isTrue);
  });

  test('suggested instance ids skip the taken ones', () {
    expect(
      agentProviderSuggestedInstanceId('codex', <String>['codex', 'codex-2']),
      'codex-3',
    );
  });
}
