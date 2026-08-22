import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry> quotaSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Provider Quotas',
    description: 'Choose quota providers and their display order.',
    keywords: <String>[
      'quota',
      'usage',
      'codex',
      'kimi',
      'grok',
      'antigravity',
      'minimax',
      'z.ai',
      'order',
      'pin',
      'pinned',
      'status bar',
    ],
    groupId: 'providers',
  ),
  SettingsSearchEntry(
    title: 'Claude Code Quotas',
    description: 'Enable Claude quotas for default and CCS accounts.',
    keywords: <String>['claude', 'quota', 'usage'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude Default Quotas',
    description: 'Configure the default Claude account independently.',
    keywords: <String>['claude', 'default', 'account', 'quota'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude Default in Usage',
    description: 'Choose whether the default Claude account appears in Usage.',
    keywords: <String>['claude', 'default', 'account', 'usage', 'visible'],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Claude CCS Profiles',
    description: 'Configure CCS alias and profile pairs for Claude quotas.',
    keywords: <String>[
      'claude',
      'ccs',
      'profile',
      'alias',
      'quota',
      'pin',
      'pinned',
      'status bar',
    ],
    groupId: 'claude',
  ),
  SettingsSearchEntry(
    title: 'Kimi API Key Variable',
    description: 'Configure the Kimi API key environment variable name.',
    keywords: <String>['kimi', 'environment', 'api key', 'KIMI_API_KEY'],
    groupId: 'credentials',
  ),
  SettingsSearchEntry(
    title: 'Quota Credential Environment',
    description:
        'Configure environment variable names for Kimi, Z.ai and MiniMax.',
    keywords: <String>[
      'environment',
      'api key',
      'kimi',
      'z.ai',
      'minimax',
      'remote',
      'host',
    ],
    groupId: 'credentials',
  ),
];
