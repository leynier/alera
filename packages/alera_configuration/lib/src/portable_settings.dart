import 'configuration_document.dart';

/// Allowlisting prevents future local settings from silently becoming cloud data.
const desktopPortableFields = <String, List<String>>{
  'general': [
    'confirmProjectRemoval',
    'confirmWorkspaceRemoval',
    'showTrayIcon',
    'showDockBadge',
    'showTrayBadge',
  ],
  'terminal': [
    'fontFamily',
    'fontSize',
    'fontWeight',
    'lineHeight',
    'paddingX',
    'paddingY',
    'cursorShape',
    'cursorBlink',
    'cursorOpacity',
    'themeName',
    'backgroundOpacity',
    'wordSeparators',
    'colorOverrides',
    'tuiScrollSensitivity',
    'clipboardOnSelect',
    'allowOsc52Clipboard',
    'showComposerByDefault',
    'toolbarCorner',
  ],
  'editor': ['tabSize', 'themeName', 'autosaveEnabled', 'autosaveDelaySeconds'],
  'keyboard': ['overrides', 'terminalPolicy'],
  'agents': [
    'agentStatusNotificationsEnabled',
    'agentStatusFinishedNotificationsEnabled',
    'defaultAgentProfileId',
    'showTabTitlesInSidebar',
  ],
  'aiTextGeneration': [
    'enabled',
    'autoGenerateAgentTitles',
    'agent',
    'selectedModelByAgent',
    'selectedThinkingByModel',
    'selectedThinkingByOperation',
    'customCommand',
    'instructionsByOperation',
    'promptSettingsByOperation',
    'timeoutSeconds',
  ],
  'aiDictation': [
    'enabled',
    'transcriptionEngine',
    'rewriteMode',
    'providerPolicy',
    'language',
    'hostFallbackEnabled',
    'providerFallbackEnabled',
    'remoteBaseUrl',
    'remoteModel',
    'codexRealtimeModel',
    'remoteProvider',
    'timeoutSeconds',
  ],
};

JsonMap portableDesktopSettings(JsonMap settings) => {
  for (final section in desktopPortableFields.entries)
    section.key: pickFields(jsonMap(settings[section.key]), section.value),
};
JsonMap pickFields(JsonMap source, Iterable<String> fields) => {
  for (final field in fields)
    if (source.containsKey(field)) field: source[field],
};
JsonMap applyDesktopSettings(
  JsonMap local,
  JsonMap portable, {
  JsonMap defaults = const {},
}) => {
  ...local,
  for (final section in desktopPortableFields.entries)
    section.key: {
      ...(jsonMap(local[section.key])
        ..removeWhere((key, _) => section.value.contains(key))),
      ...pickFields(jsonMap(defaults[section.key]), section.value),
      ...pickFields(jsonMap(portable[section.key]), section.value),
    },
};
const portableProfileFields = [
  'id',
  'name',
  'agentType',
  'command',
  'launchMode',
  'managedConfig',
  'customPrompt',
  'description',
  'quotaGroup',
];
const mobileDictationFields = [
  'enabled',
  'location',
  'engine',
  'rewriteMode',
  'language',
  'providerBaseUrl',
  'providerModel',
  'codexRealtimeModel',
  'providerTimeoutSeconds',
];

JsonMap portableCatalog(List<JsonMap> items, {List<String>? fields}) => {
  'items': {
    for (final item in items)
      item['id'] as String: fields == null ? item : pickFields(item, fields),
  },
  'order': [for (final item in items) item['id']],
};
List<JsonMap> catalogItems(Object? value) {
  final catalog = jsonMap(value);
  final items = jsonMap(catalog['items']);
  final order = (catalog['order'] as List? ?? []).cast<String>();
  final ids = <String>{...order.where(items.containsKey), ...items.keys};
  return [
    for (final id in ids) {...jsonMap(items[id]), 'id': id},
  ];
}

List<String> validateConfiguration(
  ConfigurationDocument document, {
  Set<String> ownedBlocks = const {'shared', 'desktop', 'mobile'},
}) {
  final errors = <String>[];
  if (!ownedBlocks.contains('shared')) return errors;
  final shared = jsonMap(document.json['shared']);
  final profiles = catalogItems(shared['agentProfiles']);
  final names = <String>{};
  for (final profile in profiles) {
    final name = (profile['name'] as String? ?? '').trim();
    if (name.isEmpty || !names.add(name.toLowerCase())) {
      errors.add('Agent profile names must be nonempty and unique: $name');
    }
    if ((profile['command'] as String? ?? '').trim().isEmpty) {
      errors.add('A launch command is required for $name.');
    }
  }
  final actionNames = <String>{};
  for (final action in catalogItems(shared['textActions'])) {
    final name = (action['name'] as String? ?? '').trim();
    if (name.isEmpty || !actionNames.add(name.toLowerCase())) {
      errors.add('Text action names must be nonempty and unique: $name');
    }
    if ((action['prompt'] as String? ?? '').trim().isEmpty) {
      errors.add('A prompt is required for $name.');
    }
  }
  final settings = jsonMap(jsonMap(document.json['desktop'])['settings']);
  final defaultId = jsonMap(settings['agents'])['defaultAgentProfileId'];
  if (defaultId != null && !profiles.any((p) => p['id'] == defaultId)) {
    errors.add('The default agent profile is missing.');
  }
  return errors;
}
