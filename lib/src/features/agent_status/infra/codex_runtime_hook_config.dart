part of 'codex_runtime_home_service.dart';

List<Map<String, Object?>> _definitionsFromValue(Object? value) {
  if (value is! List) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

List<Map<String, Object?>> _hookHandlers(Map<String, Object?> definition) {
  final hooks = definition['hooks'];
  if (hooks is! List) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final hook in hooks)
      if (hook is Map) Map<String, Object?>.from(hook),
  ];
}

Map<String, Object?> _hooksMap(Map<String, Object?> config) {
  final hooks = config['hooks'];
  if (hooks is Map) {
    return Map<String, Object?>.from(hooks);
  }
  return <String, Object?>{};
}

List<Map<String, Object?>> _removeManagedCommands(
  List<Map<String, Object?>> definitions,
  Set<String> managedScriptFileNames,
) {
  return _removeHookCommandsWhere(
    definitions,
    (command) => _isManagedCommand(command, managedScriptFileNames),
  );
}

List<Map<String, Object?>> _removeCodexPluginOnlyHookCommands(
  List<Map<String, Object?>> definitions,
) {
  // Plugin placeholders are only expanded for plugin-provided hooks, not for
  // hooks mirrored into Alera's plain runtime hooks.json.
  return _removeHookCommandsWhere(definitions, _isCodexPluginOnlyHookCommand);
}

List<Map<String, Object?>> _removeHookCommandsWhere(
  List<Map<String, Object?>> definitions,
  bool Function(String? command) shouldRemove,
) {
  final cleaned = <Map<String, Object?>>[];
  for (final definition in definitions) {
    final hooks = definition['hooks'];
    if (hooks is! List) {
      cleaned.add(definition);
      continue;
    }
    final nextHooks = <Object?>[
      for (final hook in hooks)
        if (hook is! Map ||
            !shouldRemove(
              Map<String, Object?>.from(hook)['command'] as String?,
            ))
          hook,
    ];
    if (nextHooks.isEmpty) {
      continue;
    }
    cleaned.add(<String, Object?>{...definition, 'hooks': nextHooks});
  }
  return cleaned;
}

bool _isManagedCommand(String? command, Set<String> managedScriptFileNames) {
  if (command == null) {
    return false;
  }
  return managedScriptFileNames.any(command.contains);
}

bool _isCodexPluginOnlyHookCommand(String? command) {
  if (command == null) {
    return false;
  }
  return _codexPluginOnlyHookPlaceholders.any(command.contains);
}

List<Map<String, Object?>> _dedupeHookDefinitions(
  List<Map<String, Object?>> definitions,
) {
  final seen = <String>{};
  return <Map<String, Object?>>[
    for (final definition in definitions)
      if (seen.add(jsonEncode(definition))) definition,
  ];
}
