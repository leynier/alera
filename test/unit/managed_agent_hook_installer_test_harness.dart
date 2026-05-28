part of 'managed_agent_hook_installer_test.dart';

void _writeJson(String path, Map<String, Object?> data) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
}

Map<String, Object?> _readJson(String path) {
  return Map<String, Object?>.from(
    jsonDecode(File(path).readAsStringSync()) as Map,
  );
}

Map<String, Object?> _hooks(String path) {
  return Map<String, Object?>.from(_readJson(path)['hooks'] as Map);
}

List<String> _commandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        if (definition['command'] is String) definition['command'] as String,
    for (final definition in definitions)
      if (definition is Map)
        for (final hook in definition['hooks'] as List? ?? const <Object?>[])
          if (hook is Map && hook['command'] is String)
            hook['command'] as String,
  ];
}

List<String> _directCommandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        for (final key in const <String>['bash', 'powershell', 'command'])
          if (definition[key] is String) definition[key] as String,
  ];
}

int _managedCommandCount(Map<String, Object?> hooks, String scriptFileName) {
  return hooks.values.fold<int>(0, (count, value) {
    final definitions = value as List? ?? const <Object?>[];
    return count +
        definitions.fold<int>(0, (innerCount, definition) {
          if (definition is! Map) {
            return innerCount;
          }
          final hooks = definition['hooks'] as List? ?? const <Object?>[];
          return innerCount +
              hooks.where((hook) {
                return hook is Map &&
                    (hook['command'] as String?)
                            ?.replaceAll(r'\', '/')
                            .contains('agent-hooks/$scriptFileName') ==
                        true;
              }).length;
        });
  });
}
