import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const String agentProviderSettingsSectionId = 'agentProviders';

const List<SettingsSearchEntry> agentProviderSearchEntries =
    <SettingsSearchEntry>[
      SettingsSearchEntry(
        title: 'Agent Chat Providers',
        description:
            'Turn providers on or off for Agent Chat and check their '
            'installation and sign-in.',
        keywords: <String>[
          'provider',
          'agent chat',
          'chat',
          'codex',
          'claude',
          'cursor',
          'opencode',
          'grok',
          'antigravity',
          'sign in',
          'login',
          'install',
          'update',
          'status',
          'host',
        ],
      ),
      SettingsSearchEntry(
        title: 'Agent Chat Models',
        description:
            'Hide, order, favorite, and add custom models for the chat '
            'picker.',
        keywords: <String>[
          'model',
          'models',
          'custom model',
          'hidden',
          'favorite',
          'order',
          'default model',
          'picker',
        ],
      ),
      SettingsSearchEntry(
        title: 'Default For New Chats',
        description: 'Choose the provider and model new chats start with.',
        keywords: <String>['default', 'new chat', 'project default'],
      ),
      SettingsSearchEntry(
        title: 'Provider Launch And Secrets',
        description:
            'Executable, arguments, environment variables, and write-only '
            'secrets for each provider.',
        keywords: <String>[
          'executable',
          'arguments',
          'args',
          'environment',
          'env',
          'secret',
          'api key',
          'token',
          'password',
        ],
      ),
    ];

/// The Providers entry under Settings > Resources. [initialHostId] and
/// [initialProviderInstanceId] open the pane on that host and row.
SettingsSectionData agentProviderSettingsSection({
  String? initialHostId,
  String? initialProviderInstanceId,
}) => SettingsSectionData(
  id: agentProviderSettingsSectionId,
  title: 'Providers',
  description:
      'Agents for Agent Chat tabs. For terminal tabs, use Agent Profiles.',
  icon: AleraIcons.comment,
  entries: agentProviderSearchEntries,
  navGroup: .resources,
  builder: (_) => AgentProviderSettingsPane(
    initialHostId: initialHostId,
    initialProviderInstanceId: initialProviderInstanceId,
  ),
);
