import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final List<SettingsSearchEntry>
quotaSearchEntries = buildSettingsSearchEntryCatalog(const {
  'providers': {
    'Provider Quotas': SettingsSearchEntryDetails(
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
    ),
  },
  'claude': {
    'Claude Code Quotas': SettingsSearchEntryDetails(
      description: 'Enable Claude quotas for default and CCS accounts.',
      keywords: <String>['claude', 'quota', 'usage'],
    ),
    'Claude Default Quotas': SettingsSearchEntryDetails(
      description: 'Configure the default Claude account independently.',
      keywords: <String>['claude', 'default', 'account', 'quota'],
    ),
    'Claude Default in Usage': SettingsSearchEntryDetails(
      description:
          'Choose whether the default Claude account appears in Usage.',
      keywords: <String>['claude', 'default', 'account', 'usage', 'visible'],
    ),
    'Claude CCS Profiles': SettingsSearchEntryDetails(
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
    ),
  },
  'credentials': {
    'Kimi API Key Variable': SettingsSearchEntryDetails(
      description: 'Configure the Kimi API key environment variable name.',
      keywords: <String>['kimi', 'environment', 'api key', 'KIMI_API_KEY'],
    ),
    'Quota Credential Environment': SettingsSearchEntryDetails(
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
    ),
  },
});
