import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';

// Older editors drop future built-in ids and custom-key metadata when saving.
JsonMap preserveQuickKeys(JsonMap retained, JsonMap local) {
  final priorKeys = {
    for (final key in retained['customKeys'] as List? ?? [])
      jsonMap(key)['id']: jsonMap(key),
  };
  final keys = [
    for (final key in local['customKeys'] as List? ?? [])
      {...?priorKeys[jsonMap(key)['id']], ...jsonMap(key)},
  ];
  final supported = {
    ...builtInTerminalAccessoryKeysById.keys,
    ...priorKeys.keys,
    for (final key in keys) key['id'],
  };
  List<Object?> ids(String field) {
    final result = List<Object?>.from(local[field] as List? ?? []);
    final previous = retained[field] as List? ?? [];
    for (var i = 0; i < previous.length; i++) {
      final id = previous[i];
      if (supported.contains(id) || result.contains(id)) continue;
      var position = 0;
      for (var j = i - 1; j >= 0; j--) {
        final neighbor = result.indexOf(previous[j]);
        if (neighbor >= 0) {
          position = neighbor + 1;
          break;
        }
      }
      result.insert(position, id);
    }
    return result;
  }

  return {
    ...retained,
    ...local,
    'customKeys': keys,
    'orderedIds': ids('orderedIds'),
    'hiddenIds': ids('hiddenIds'),
  };
}
