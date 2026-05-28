part of 'codex_runtime_home_service.dart';

extension _CodexRuntimeHomeServiceConfigSync on CodexRuntimeHomeService {
  void _syncSystemConfig(Directory runtimeHome) {
    final systemPath = p.join(_systemHomePath, 'config.toml');
    final runtimePath = p.join(runtimeHome.path, 'config.toml');
    final systemExists = File(systemPath).existsSync();
    final runtimeExists = File(runtimePath).existsSync();
    final systemConfig = _normalizeDeprecatedHookFeatureFlag(
      systemExists ? _readTextFile(systemPath) : '',
    );
    if (!runtimeExists) {
      _writeTextAtomically(
        runtimePath,
        _ensureHooksFeatureEnabled(
          _stripRuntimeOwnedTomlSections(systemConfig),
        ),
      );
      return;
    }
    final runtimeConfig = _readTextFile(runtimePath);
    final merged = _ensureHooksFeatureEnabled(
      _mergeSystemConfigIntoRuntime(runtimeConfig, systemConfig),
    );
    if (merged != runtimeConfig) {
      _writeTextAtomically(runtimePath, merged);
    }
  }

  String _normalizeDeprecatedHookFeatureFlag(String config) {
    if (!config.contains('codex_hooks')) {
      return config;
    }
    final lines = config.split('\n');
    final featureSections = _tomlSections(
      config,
    ).where((section) => _sectionHeaderKey(section.header) == '[features]');
    for (final section in featureSections.toList(growable: false).reversed) {
      final start = section.start + 1;
      final end = section.start + section.block.split('\n').length;
      final deprecated = <int>[];
      var hasHooks = false;
      for (var index = start; index < end; index++) {
        final line = lines[index];
        if (RegExp(r'^[ \t]*hooks[ \t]*=').hasMatch(line)) {
          hasHooks = true;
        }
        if (RegExp(r'^[ \t]*codex_hooks[ \t]*=').hasMatch(line)) {
          deprecated.add(index);
        }
      }
      if (deprecated.isEmpty) {
        continue;
      }
      if (!hasHooks) {
        final first = deprecated.removeAt(0);
        lines[first] = lines[first].replaceFirstMapped(
          RegExp(r'^([ \t]*)codex_hooks([ \t]*=)'),
          (match) => '${match.group(1)}hooks${match.group(2)}',
        );
      }
      for (final index in deprecated.reversed) {
        lines.removeAt(index);
      }
    }
    return lines.join('\n');
  }

  String _mergeSystemConfigIntoRuntime(
    String runtimeConfig,
    String systemConfig,
  ) {
    final runtimeSections = _tomlSections(runtimeConfig);
    final systemProjectKeys = _tomlSections(systemConfig)
        .where((section) => _isProjectSection(section.header))
        .map((section) => _sectionHeaderKey(section.header))
        .toSet();
    return _joinTomlBlocks(<String>[
      _stripRuntimeOwnedTomlSections(systemConfig),
      for (final section in runtimeSections)
        if (_isHookStateSection(section.header) ||
            (_isProjectSection(section.header) &&
                !systemProjectKeys.contains(_sectionHeaderKey(section.header))))
          section.block,
    ]);
  }

  String _ensureHooksFeatureEnabled(String config) {
    final sections = _tomlSections(config);
    _TomlSection? featureSection;
    for (final section in sections) {
      if (_sectionHeaderKey(section.header) == '[features]') {
        featureSection = section;
        break;
      }
    }
    if (featureSection == null) {
      return _joinTomlBlocks(<String>[config, '[features]\nhooks = true']);
    }

    final lines = config.split('\n');
    final start = featureSection.start + 1;
    final end = featureSection.start + featureSection.block.split('\n').length;
    var multilineState = const _TomlMultilineState();
    var hooksLineIndex = -1;
    for (var index = start; index < end; index++) {
      final line = lines[index];
      if (!_isInsideTomlMultilineString(multilineState) &&
          RegExp(r'^[ \t]*hooks[ \t]*=').hasMatch(line)) {
        hooksLineIndex = index;
        break;
      }
      multilineState = _updateTomlMultilineState(multilineState, line);
    }
    if (hooksLineIndex >= 0) {
      lines[hooksLineIndex] = lines[hooksLineIndex].replaceFirstMapped(
        RegExp(r'^([ \t]*)hooks[ \t]*=.*$'),
        (match) => '${match.group(1)}hooks = true',
      );
      return _joinTomlBlocks(<String>[lines.join('\n')]);
    }

    var insertIndex = end;
    while (insertIndex > start && lines[insertIndex - 1].trim().isEmpty) {
      insertIndex -= 1;
    }
    lines.insert(insertIndex, 'hooks = true');
    return _joinTomlBlocks(<String>[lines.join('\n')]);
  }

  String _stripRuntimeOwnedTomlSections(String config) {
    final sections = _tomlSections(config);
    final firstStart = sections.isEmpty ? -1 : sections.first.start;
    final preamble = firstStart < 0
        ? config
        : config.split('\n').take(firstStart).join('\n');
    return _joinTomlBlocks(<String>[
      preamble,
      for (final section in sections)
        if (!_isHookStateSection(section.header)) section.block,
    ]);
  }
}
