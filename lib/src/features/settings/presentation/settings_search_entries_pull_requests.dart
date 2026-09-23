import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';

const Map<String, Map<String, SettingsSearchEntryDetails>>
pullRequestApplicationSearchGroups =
    <String, Map<String, SettingsSearchEntryDetails>>{
      'pullRequests': <String, SettingsSearchEntryDetails>{
        'Show Pull Request Status': SettingsSearchEntryDetails(
          description: 'Show hosted review and CI state beside each workspace.',
          keywords: <String>[
            'pull request',
            'pr',
            'checks',
            'ci',
            'sidebar',
            'draft',
            'merged',
          ],
        ),
        'Notify When Checks Fail': SettingsSearchEntryDetails(
          description:
              'Show a native notification when PR checks start failing.',
          keywords: <String>[
            'pull request',
            'pr',
            'checks',
            'ci',
            'failure',
            'notification',
          ],
        ),
      },
    };
