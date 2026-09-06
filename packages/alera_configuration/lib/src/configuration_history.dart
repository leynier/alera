import 'configuration_document.dart';
import 'portable_settings.dart';

/// Restoring supported fields must not roll back settings introduced by newer clients.
ConfigurationDocument configurationForRestore(
  ConfigurationDocument current,
  ConfigurationDocument historical,
  Set<String> ownedBlocks,
) {
  final blocks = <String, Object?>{};
  if (ownedBlocks.contains('desktop')) {
    final now = jsonMap(current.json['desktop']);
    final old = jsonMap(historical.json['desktop']);
    final settings = jsonMap(now['settings']);
    final oldSettings = jsonMap(old['settings']);
    blocks['desktop'] = {
      ...old,
      ...now,
      'settings': {
        ...oldSettings,
        ...settings,
        for (final entry in desktopPortableFields.entries)
          entry.key: _fields(
            settings[entry.key],
            oldSettings[entry.key],
            entry.value,
          ),
      },
    };
  }
  if (ownedBlocks.contains('shared')) {
    final now = jsonMap(current.json['shared']);
    final old = jsonMap(historical.json['shared']);
    blocks['shared'] = {
      ...old,
      ...now,
      'agentProfiles': _catalog(
        now['agentProfiles'],
        old['agentProfiles'],
        portableProfileFields,
      ),
      'textActions': _catalog(now['textActions'], old['textActions'], [
        'id',
        'name',
        'prompt',
        'enabled',
        'agentOverride',
        'modelOverride',
        'reasoningByModel',
      ]),
    };
  }
  if (ownedBlocks.contains('mobile')) {
    final now = jsonMap(current.json['mobile']);
    final old = jsonMap(historical.json['mobile']);
    blocks['mobile'] = {
      ...old,
      ...now,
      'dictation': _fields(
        now['dictation'],
        old['dictation'],
        mobileDictationFields,
      ),
      'codex': _fields(now['codex'], old['codex'], [
        'model',
        'reasoningEffort',
        'speedMode',
        'permissionMode',
        'planMode',
      ]),
      'quickKeys': _fields(now['quickKeys'], old['quickKeys'], [
        'version',
        'orderedIds',
        'hiddenIds',
        'customKeys',
      ]),
    };
  }
  return current.withBlocks(blocks);
}

JsonMap _fields(Object? current, Object? historical, List<String> supported) =>
    {...jsonMap(historical), ...jsonMap(current)}
      ..removeWhere((key, _) => supported.contains(key))
      ..addAll(pickFields(jsonMap(historical), supported));

JsonMap _catalog(Object? current, Object? historical, List<String> fields) {
  final now = jsonMap(current);
  final old = jsonMap(historical);
  final currentItems = jsonMap(now['items']);
  final oldItems = jsonMap(old['items']);
  return {
    ...old,
    ...now,
    'order': old['order'] ?? <String>[],
    'items': {
      for (final entry in oldItems.entries)
        entry.key: _fields(currentItems[entry.key], entry.value, fields),
    },
  };
}
