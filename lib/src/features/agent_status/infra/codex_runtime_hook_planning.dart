part of 'codex_runtime_home_service.dart';

extension _CodexRuntimeHomeServiceHookPlanning on CodexRuntimeHomeService {
  _RuntimeHookPlan _runtimeHooksWithSystemUserHooks(
    _CodexRuntimeHookDescriptor descriptor,
  ) {
    final systemConfig = _readJsonObject(descriptor.systemConfigPath);
    if (systemConfig == null || systemConfig['hooks'] is! Map) {
      return _RuntimeHookPlan(
        <String, Object?>{},
        <_MirroredRuntimeUserHookTrustEntry>[],
      );
    }
    final trustedSystemHookSignatures = _trustedSystemUserHookSignatures(
      descriptor,
      Map<String, Object?>.from(systemConfig['hooks'] as Map),
    );
    final nextHooks = <String, Object?>{};
    for (final entry in Map<String, Object?>.from(
      systemConfig['hooks'] as Map,
    ).entries) {
      final definitions = _definitionsFromValue(entry.value);
      final userDefinitions = _removeCodexPluginOnlyHookCommands(
        _removeManagedCommands(definitions, descriptor.managedScriptFileNames),
      );
      if (userDefinitions.isNotEmpty) {
        nextHooks[entry.key] = _dedupeHookDefinitions(userDefinitions);
      }
    }
    return _RuntimeHookPlan(
      nextHooks,
      _collectMirroredRuntimeUserHookTrustEntries(
        runtimeConfigPath: descriptor.configPath,
        runtimeHooks: nextHooks,
        trustedSystemHookSignatures: trustedSystemHookSignatures,
        managedScriptFileNames: descriptor.managedScriptFileNames,
      ),
    );
  }

  Map<String, bool> _trustedSystemUserHookSignatures(
    _CodexRuntimeHookDescriptor descriptor,
    Map<String, Object?> systemHooks,
  ) {
    final signatures = <String, bool>{};
    final trustEntries = _readHookTrustEntries(descriptor.systemTomlPath);
    final trustedHashesByEvent = _trustedSystemHookHashesByEvent(
      descriptor,
      trustEntries,
    );
    for (final eventEntry in systemHooks.entries) {
      final definitions = _definitionsFromValue(eventEntry.value);
      for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
        final definition = definitions[groupIndex];
        final handlers = _hookHandlers(definition);
        for (
          var handlerIndex = 0;
          handlerIndex < handlers.length;
          handlerIndex++
        ) {
          final hook = handlers[handlerIndex];
          if (_isManagedCommand(
            hook['command'] as String?,
            descriptor.managedScriptFileNames,
          )) {
            continue;
          }
          final entry = _createTrustEntry(
            sourcePath: descriptor.systemConfigPath,
            eventName: eventEntry.key,
            groupIndex: groupIndex,
            handlerIndex: handlerIndex,
            definition: definition,
            hook: hook,
          );
          if (entry == null) {
            continue;
          }
          final expectedHash = _computeTrustedHash(entry);
          final state = trustEntries[_computeTrustKey(entry)];
          final enabled = state?.trustedHash == expectedHash
              ? state?.enabled != false
              : trustedHashesByEvent[entry.eventLabel]?[expectedHash];
          if (enabled == null) {
            continue;
          }
          final signature = _trustSignature(entry);
          if (enabled || !signatures.containsKey(signature)) {
            signatures[signature] = enabled;
          }
        }
      }
    }
    return signatures;
  }

  Map<String, Map<String, bool>> _trustedSystemHookHashesByEvent(
    _CodexRuntimeHookDescriptor descriptor,
    Map<String, _CodexHookTrustState> trustEntries,
  ) {
    final trustedHashesByEvent = <String, Map<String, bool>>{};
    final canonicalSystemHooksPath = _canonicalTrustPath(
      descriptor.systemConfigPath,
    );
    for (final entry in trustEntries.entries) {
      final parsed = _parseTrustKey(entry.key);
      final trustedHash = entry.value.trustedHash;
      if (parsed == null || trustedHash == null) {
        continue;
      }
      if (_canonicalTrustPath(parsed.sourcePath) != canonicalSystemHooksPath) {
        continue;
      }
      final hashes = trustedHashesByEvent.putIfAbsent(
        parsed.eventLabel,
        () => <String, bool>{},
      );
      final enabled = entry.value.enabled != false;
      // Codex trust keys include hook indices; after reordering, the hash still
      // proves the same event and command identity was approved.
      if (enabled || !hashes.containsKey(trustedHash)) {
        hashes[trustedHash] = enabled;
      }
    }
    return trustedHashesByEvent;
  }

  List<_MirroredRuntimeUserHookTrustEntry>
  _collectMirroredRuntimeUserHookTrustEntries({
    required String runtimeConfigPath,
    required Map<String, Object?> runtimeHooks,
    required Map<String, bool> trustedSystemHookSignatures,
    required Set<String> managedScriptFileNames,
  }) {
    if (trustedSystemHookSignatures.isEmpty) {
      return const <_MirroredRuntimeUserHookTrustEntry>[];
    }
    final entries = <_MirroredRuntimeUserHookTrustEntry>[];
    for (final eventEntry in runtimeHooks.entries) {
      final definitions = _definitionsFromValue(eventEntry.value);
      for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
        final definition = definitions[groupIndex];
        final handlers = _hookHandlers(definition);
        for (
          var handlerIndex = 0;
          handlerIndex < handlers.length;
          handlerIndex++
        ) {
          final hook = handlers[handlerIndex];
          if (_isManagedCommand(
            hook['command'] as String?,
            managedScriptFileNames,
          )) {
            continue;
          }
          final entry = _createTrustEntry(
            sourcePath: runtimeConfigPath,
            eventName: eventEntry.key,
            groupIndex: groupIndex,
            handlerIndex: handlerIndex,
            definition: definition,
            hook: hook,
          );
          if (entry == null) {
            continue;
          }
          final enabled = trustedSystemHookSignatures[_trustSignature(entry)];
          if (enabled != null) {
            entries.add(_MirroredRuntimeUserHookTrustEntry(entry, enabled));
          }
        }
      }
    }
    return entries;
  }

  List<_CodexHookTrustEntry> _collectManagedTrustEntries({
    required String sourcePath,
    required String eventName,
    required List<Map<String, Object?>> definitions,
    required Set<String> managedScriptFileNames,
  }) {
    final entries = <_CodexHookTrustEntry>[];
    for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
      final definition = definitions[groupIndex];
      final handlers = _hookHandlers(definition);
      for (
        var handlerIndex = 0;
        handlerIndex < handlers.length;
        handlerIndex++
      ) {
        final hook = handlers[handlerIndex];
        if (!_isManagedCommand(
          hook['command'] as String?,
          managedScriptFileNames,
        )) {
          continue;
        }
        final entry = _createTrustEntry(
          sourcePath: sourcePath,
          eventName: eventName,
          groupIndex: groupIndex,
          handlerIndex: handlerIndex,
          definition: definition,
          hook: hook,
        );
        if (entry != null) {
          entries.add(entry);
        }
      }
    }
    return entries;
  }

  _CodexHookTrustEntry? _createTrustEntry({
    required String sourcePath,
    required String eventName,
    required int groupIndex,
    required int handlerIndex,
    required Map<String, Object?> definition,
    required Map<String, Object?> hook,
  }) {
    final command = hook['command'];
    if (command is! String ||
        command.isEmpty ||
        !_codexEventLabels.containsKey(eventName)) {
      return null;
    }
    return _CodexHookTrustEntry(
      sourcePath: sourcePath,
      eventLabel: _codexEventLabel(eventName),
      groupIndex: groupIndex,
      handlerIndex: handlerIndex,
      command: command,
      timeoutSec: hook['timeout'] is num
          ? (hook['timeout'] as num).toInt()
          : null,
      async: hook['async'] is bool ? hook['async'] as bool : null,
      matcher: definition['matcher'] is String
          ? definition['matcher'] as String
          : null,
      statusMessage: hook['statusMessage'] is String
          ? hook['statusMessage'] as String
          : null,
    );
  }

  void _upsertHookTrustEntries(
    String configPath,
    Iterable<_MirroredRuntimeUserHookTrustEntry> entries,
  ) {
    final list = entries.toList(growable: false);
    if (list.isEmpty) {
      return;
    }
    final existing = File(configPath).existsSync()
        ? _readTextFile(configPath)
        : '';
    var updated = existing;
    for (final mirrored in list) {
      updated = _upsertTrustBlock(
        updated,
        _computeTrustKey(mirrored.entry),
        _computeTrustedHash(mirrored.entry),
        mirrored.enabled,
      );
    }
    if (updated != existing) {
      _writeTextAtomically(configPath, updated);
    }
  }

  void _removeStaleRuntimeTrustEntries({
    required String tomlPath,
    required String runtimeHooksPath,
    required List<_CodexHookTrustEntry> expectedEntries,
  }) {
    final expected = <String, String>{
      for (final entry in expectedEntries)
        _computeTrustKey(entry): _computeTrustedHash(entry),
    };
    final canonicalRuntimeHooksPath = _canonicalTrustPath(runtimeHooksPath);
    final stale = <String>[];
    for (final entry in _readHookTrustEntries(tomlPath).entries) {
      final parsed = _parseTrustKey(entry.key);
      if (parsed == null ||
          _canonicalTrustPath(parsed.sourcePath) != canonicalRuntimeHooksPath) {
        continue;
      }
      if (expected[entry.key] != entry.value.trustedHash) {
        stale.add(entry.key);
      }
    }
    _removeHookTrustEntries(tomlPath, stale);
  }

  void _removeMatchingTrustEntries(
    String configPath,
    List<_CodexHookTrustEntry> entries,
  ) {
    if (entries.isEmpty) {
      return;
    }
    final existing = _readHookTrustEntries(configPath);
    final keys = <String>[];
    for (final entry in entries) {
      final key = _computeTrustKey(entry);
      if (existing[key]?.trustedHash == _computeTrustedHash(entry)) {
        keys.add(key);
      }
    }
    _removeHookTrustEntries(configPath, keys);
  }

  void _removeHookTrustEntries(String configPath, List<String> keys) {
    if (keys.isEmpty || !File(configPath).existsSync()) {
      return;
    }
    final existing = _readTextFile(configPath);
    var updated = existing;
    for (final key in keys) {
      updated = _removeTrustBlock(updated, key);
    }
    if (updated != existing) {
      _writeTextAtomically(configPath, updated);
    }
  }

  Map<String, _CodexHookTrustState> _readHookTrustEntries(String configPath) {
    final result = <String, _CodexHookTrustState>{};
    final file = File(configPath);
    if (!file.existsSync()) {
      return result;
    }
    final content = _readTextFile(configPath);
    final headerRegex = RegExp(
      r'^[ \t]*\[hooks\.state\."((?:[^"\\]|\\.)*)"\][ \t]*(?:#[^\r\n]*)?$',
    );
    var cursor = 0;
    var multilineState = const _TomlMultilineState();
    while (cursor < content.length) {
      final newlineIndex = content.indexOf('\n', cursor);
      final lineEnd = newlineIndex < 0 ? content.length : newlineIndex;
      final line = content
          .substring(cursor, lineEnd)
          .replaceFirst(RegExp(r'\r$'), '');
      final nextCursor = newlineIndex < 0 ? content.length : newlineIndex + 1;
      if (_isInsideTomlMultilineString(multilineState)) {
        multilineState = _updateTomlMultilineState(multilineState, line);
        cursor = nextCursor;
        continue;
      }
      final match = headerRegex.firstMatch(line);
      if (match != null) {
        final after = content.substring(nextCursor);
        final nextHeader = _findNextTableHeader(after);
        final blockEnd = nextHeader < 0
            ? content.length
            : nextCursor + nextHeader;
        final blockText = content.substring(nextCursor, blockEnd);
        final hashMatch = RegExp(
          r'^[ \t]*trusted_hash[ \t]*=[ \t]*"((?:[^"\\]|\\.)*)"',
          multiLine: true,
        ).firstMatch(blockText);
        final enabledMatch = RegExp(
          r'^[ \t]*enabled[ \t]*=[ \t]*(true|false)[ \t\r]*(?:#.*)?$',
          multiLine: true,
        ).firstMatch(blockText);
        result[_unescapeTomlString(match.group(1)!)] = _CodexHookTrustState(
          trustedHash: hashMatch == null
              ? null
              : _unescapeTomlString(hashMatch.group(1)!),
          enabled: enabledMatch == null
              ? null
              : enabledMatch.group(1) == 'true',
        );
      }
      multilineState = _updateTomlMultilineState(multilineState, line);
      cursor = nextCursor;
    }
    return result;
  }

  String _upsertTrustBlock(
    String content,
    String key,
    String hash,
    bool enabled,
  ) {
    final headerPattern = _tomlHeaderPattern('hooks.state', key);
    final match = headerPattern.firstMatch(content);
    final block = <String>[
      '[hooks.state."${_escapeTomlString(key)}"]',
      'enabled = $enabled',
      'trusted_hash = "${_escapeTomlString(hash)}"',
    ].join('\n');
    if (match == null) {
      final separator = content.isEmpty
          ? ''
          : content.endsWith('\n\n')
          ? ''
          : content.endsWith('\n')
          ? '\n'
          : '\n\n';
      return '$content$separator$block\n';
    }
    final cutStart = match.start + ((match.group(1) ?? '').length);
    final afterHeader = content.substring(match.end);
    final nextHeader = _findNextTableHeader(afterHeader);
    final cutEnd = nextHeader < 0 ? content.length : match.end + nextHeader;
    return '${content.substring(0, cutStart)}$block\n${content.substring(cutEnd)}';
  }

  String _removeTrustBlock(String content, String key) {
    final headerPattern = _tomlHeaderPattern('hooks.state', key);
    final match = headerPattern.firstMatch(content);
    if (match == null) {
      return content;
    }
    final cutStart = match.start + ((match.group(1) ?? '').length);
    final afterHeader = content.substring(match.end);
    final nextHeader = _findNextTableHeader(afterHeader);
    final cutEnd = nextHeader < 0 ? content.length : match.end + nextHeader;
    return content.substring(0, cutStart) + content.substring(cutEnd);
  }

  RegExp _tomlHeaderPattern(String prefix, String key) {
    final escapedPrefix = RegExp.escape(prefix);
    final escaped = RegExp.escape(_escapeTomlString(key));
    return RegExp(
      '(^|\\r?\\n)[ \\t]*\\[$escapedPrefix\\."$escaped"\\][ \\t]*(?:#[^\\r\\n]*)?(?=\\r?\\n|\\\$)',
    );
  }
}
