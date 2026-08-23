import 'package:alera/src/features/settings/presentation/settings_search_entry_catalog.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';

final List<SettingsSearchEntry> textActionsSearchEntries =
    buildSettingsSearchEntryCatalog(const {
      'actions': {
        'Text Actions': SettingsSearchEntryDetails(
          description: 'Create reusable replacements for selected text.',
          keywords: <String>[
            'text',
            'action',
            'replace',
            'selection',
            'ai',
            'prompt',
          ],
        ),
        'New Action': SettingsSearchEntryDetails(
          description: 'Create a reusable text replacement action.',
          keywords: <String>['create', 'add'],
        ),
        'Enabled': SettingsSearchEntryDetails(
          description: 'Show an action in the Text Actions menu.',
          keywords: <String>['enable', 'disable'],
        ),
        'Agent And Model': SettingsSearchEntryDetails(
          description: 'Choose the CLI and model for an action.',
          keywords: <String>['agent', 'model', 'reasoning'],
        ),
        'Duplicate And Reorder': SettingsSearchEntryDetails(
          description: 'Copy actions and arrange their menu order.',
          keywords: <String>['copy', 'drag', 'sort', 'order'],
        ),
        'Delete': SettingsSearchEntryDetails(
          description: 'Remove a text action after confirmation.',
          keywords: <String>['remove', 'destructive'],
        ),
      },
    });
