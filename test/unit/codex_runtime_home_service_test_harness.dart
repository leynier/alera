part of 'codex_runtime_home_service_test.dart';

CodexRuntimeHomeService _serviceWithFailingResourceLinks({
  required Directory home,
  required Directory support,
}) {
  return CodexRuntimeHomeService(
    homeDirectory: home.path,
    applicationSupportDirectory: () async => support,
    platform: .posix,
    environment: <String, String>{'HOME': home.path},
    resourceLinkCreator: ({required sourcePath, required targetPath}) =>
        throw const FileSystemException('symlinks disabled'),
  );
}

String _markerFingerprint(File marker) {
  final decoded = jsonDecode(marker.readAsStringSync()) as Map;
  return decoded['sourceFingerprint'] as String;
}

Map<String, Object?> _userHook(String command) {
  return _userHookCommands(<String>[command]);
}

Map<String, Object?> _userHookCommands(List<String> commands) {
  return <String, Object?>{
    'hooks': <Object?>[
      for (final command in commands)
        <String, Object?>{'type': 'command', 'command': command},
    ],
  };
}

String _trustBlock({
  required String key,
  required bool enabled,
  required String trustedHash,
}) {
  return '[hooks.state."${_escapeTomlString(key)}"]\n'
      'enabled = $enabled\n'
      'trusted_hash = "$trustedHash"\n';
}

void _writeJson(String path, Map<String, Object?> value) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

Map<String, Object?> _readJson(String path) {
  return Map<String, Object?>.from(
    jsonDecode(File(path).readAsStringSync()) as Map,
  );
}

Map<String, Object?> _hooks(String configPath) {
  final decoded = _readJson(configPath);
  return Map<String, Object?>.from(decoded['hooks'] as Map);
}

List<String> _commandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        for (final hook in (definition['hooks'] as List? ?? const <Object?>[]))
          if (hook is Map && hook['command'] is String)
            hook['command'] as String,
  ];
}

int _managedCommandCount(Map<String, Object?> hooks, String fileName) {
  var count = 0;
  for (final event in hooks.values) {
    if (event is! List) {
      continue;
    }
    for (final definition in event) {
      if (definition is! Map) {
        continue;
      }
      final hookEntries = definition['hooks'];
      if (hookEntries is! List) {
        continue;
      }
      for (final hook in hookEntries) {
        if (hook is Map &&
            hook['command'] is String &&
            (hook['command'] as String).contains(fileName)) {
          count += 1;
        }
      }
    }
  }
  return count;
}

String _escapeTomlString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
