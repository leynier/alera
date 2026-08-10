part of 'mobile_codex_state.dart';

String _mobileCodexItemDetails(Map<String, Object?> item) {
  final source = _mobileCodexItemDetailsSource(item);
  if (source == null) return '';
  final value = item[source];
  if (value is String) return value;
  return '';
}

String? _mobileCodexItemDetailsSource(Map<String, Object?> item) {
  for (final key in const <String>[
    'aggregatedOutput',
    'output',
    'result',
    'error',
    'diff',
    'commandOutput',
    'changes',
    'contentItems',
    'action',
  ]) {
    final value = item[key];
    if (value == null) continue;
    if (value is String) {
      if (value.isNotEmpty) return key;
    } else {
      return key;
    }
  }
  return null;
}

Map<String, Object?> _mobileCodexItemMetadata(Map<String, Object?> item) {
  return <String, Object?>{
    'itemType': item['type'],
    'type': item['type'],
    'query': item['query'],
    'url': item['url'],
    'action': item['action'],
    'results': item['results'],
    'changes': item['changes'],
    'changesCount':
        item['changesCount'] ??
        (item['changes'] is List ? (item['changes'] as List).length : null),
    'arguments': item['arguments'],
    'result': item['result'],
    'error': item['error'],
    'contentItems': item['contentItems'],
    'commandActions': item['commandActions'],
    'durationMs': item['durationMs'],
    'status': item['status'],
    'server': item['server'],
    'tool': item['tool'],
    'namespace': item['namespace'],
    'appContext': item['appContext'],
    'pluginId': item['pluginId'],
    'readOnlyHint': item['readOnlyHint'],
    'success': item['success'],
    'path': item['path'],
    'revisedPrompt': item['revisedPrompt'],
    'savedPath': item['savedPath'],
    'aggregatedOutput': _mobileNonStringItemDetail(item['aggregatedOutput']),
    'output': _mobileNonStringItemDetail(item['output']),
    'diff': _mobileNonStringItemDetail(item['diff']),
    'commandOutput': _mobileNonStringItemDetail(item['commandOutput']),
    'detailsSource': ?_mobileCodexItemDetailsSource(item),
  };
}

Object? _mobileNonStringItemDetail(Object? value) =>
    value is String ? null : value;
