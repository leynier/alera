import 'package:alera/src/features/settings/presentation/settings_sections.dart';

const List<SettingsSearchEntry> textActionsSearchEntries =
    <SettingsSearchEntry>[
      SettingsSearchEntry(
        title: 'Text Actions',
        description: 'Create reusable replacements for selected text.',
        keywords: <String>[
          'text',
          'action',
          'replace',
          'selection',
          'ai',
          'prompt',
        ],
        groupId: 'actions',
      ),
      SettingsSearchEntry(
        title: 'New Action',
        description: 'Create a reusable text replacement action.',
        keywords: <String>['create', 'add'],
        groupId: 'actions',
      ),
      SettingsSearchEntry(
        title: 'Enabled',
        description: 'Show an action in the Text Actions menu.',
        keywords: <String>['enable', 'disable'],
        groupId: 'actions',
      ),
      SettingsSearchEntry(
        title: 'Agent And Model',
        description: 'Choose the CLI and model for an action.',
        keywords: <String>['agent', 'model', 'reasoning'],
        groupId: 'actions',
      ),
      SettingsSearchEntry(
        title: 'Duplicate And Reorder',
        description: 'Copy actions and arrange their menu order.',
        keywords: <String>['copy', 'drag', 'sort', 'order'],
        groupId: 'actions',
      ),
      SettingsSearchEntry(
        title: 'Delete',
        description: 'Remove a text action after confirmation.',
        keywords: <String>['remove', 'destructive'],
        groupId: 'actions',
      ),
    ];
