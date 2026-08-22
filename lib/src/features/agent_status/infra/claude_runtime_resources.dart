part of 'claude_runtime_home_service.dart';

extension _ClaudeRuntimeResources on ClaudeRuntimeHomeService {
  Future<Directory> _runtimeHomeDirectory() async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'agent-runtime-homes', 'claude', 'home'),
    );
    directory.createSync(recursive: true);
    return directory;
  }

  Directory _sourceConfigDirectory(Directory runtimeHome) {
    final inherited = _environment['CLAUDE_CONFIG_DIR']?.trim();
    if (inherited != null &&
        inherited.isNotEmpty &&
        !_samePath(inherited, runtimeHome.path)) {
      return Directory(inherited);
    }
    return Directory(p.join(_homeDirectory, '.claude'));
  }

  /// CCS root: `$CCS_DIR` or `~/.ccs`.
  String _ccsRootDirectory() {
    final fromEnv = _environment['CCS_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return p.join(_homeDirectory, '.ccs');
  }

  /// CCS settings files that still need Alera hooks because CCS aliases
  /// override `CLAUDE_CONFIG_DIR` away from the runtime overlay.
  ///
  /// `~/.claude/settings.json` is not an install target: Grok scans it by
  /// default, so Alera commands there steal Grok/Cursor identity.
  List<String> _ccsClaudeSettingsPaths() {
    return _collectClaudeSettingsPaths(includeUserLeftovers: false);
  }

  /// User Claude files that older installs wrote. Strip leftovers on remove
  /// and host start; never treat them as required for `status()`.
  List<String> _leftoverClaudeSettingsPaths() {
    return _collectClaudeSettingsPaths(includeUserLeftovers: true);
  }

  List<String> _collectClaudeSettingsPaths({
    required bool includeUserLeftovers,
  }) {
    final seen = <String>{};
    final paths = <String>[];

    void consider(String path) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return;
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.link) {
        return;
      }
      final resolved = _resolvedWritablePath(path);
      if (!File(resolved).existsSync()) {
        return;
      }
      final key = _absoluteNormalizedPath(resolved);
      if (seen.add(key)) {
        paths.add(resolved);
      }
    }

    if (includeUserLeftovers) {
      final claudeHome = p.join(_homeDirectory, '.claude');
      consider(p.join(claudeHome, 'settings.json'));
      consider(p.join(claudeHome, 'settings.local.json'));
    }

    final ccsRoot = _ccsRootDirectory();
    consider(p.join(ccsRoot, 'shared', 'settings.json'));

    final instancesDir = Directory(p.join(ccsRoot, 'instances'));
    if (instancesDir.existsSync()) {
      for (final entity in instancesDir.listSync(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final settingsPath = p.join(entity.path, 'settings.json');
        final type = FileSystemEntity.typeSync(
          settingsPath,
          followLinks: false,
        );
        // Symlinks usually resolve to shared settings (already considered).
        // Only install into private per-instance settings files.
        if (type == FileSystemEntityType.file) {
          consider(settingsPath);
        }
      }
    }

    return paths;
  }

  _ClaudeRuntimeHookDescriptor _descriptor(Directory runtimeHome) {
    final extension = switch (_platform) {
      ManagedAgentHookPlatform.posix => 'sh',
      ManagedAgentHookPlatform.windows => 'cmd',
    };
    final scriptFileName = 'alera-claude-hook.$extension';
    return _ClaudeRuntimeHookDescriptor(
      settingsPath: p.join(runtimeHome.path, 'settings.json'),
      scriptPath: p.join(
        _homeDirectory,
        '.alera',
        'agent-hooks',
        scriptFileName,
      ),
      managedScriptFileNames: <String>{scriptFileName},
    );
  }

  void _syncRuntimeResources(Directory runtimeHome, Directory source) {
    final expected = <String, String>{};
    if (source.existsSync()) {
      for (final entity in source.listSync(followLinks: false)) {
        final entryName = p.basename(entity.path);
        if (entryName == 'settings.json') {
          continue;
        }
        expected[entryName] = entity.path;
      }
    }

    final legacyConfig = File(p.join(_homeDirectory, '.claude.json'));
    if (_samePath(source.path, p.join(_homeDirectory, '.claude')) &&
        legacyConfig.existsSync()) {
      expected['.claude.json'] = legacyConfig.path;
    }

    for (final entry in expected.entries) {
      _syncLinkedResource(
        runtimeHomePath: runtimeHome.path,
        entryName: entry.key,
        sourcePath: entry.value,
      );
    }
    _removeStaleRuntimeResources(runtimeHome, expected);
  }

  Future<void> _syncKeychainCredentials(Directory runtimeHome) async {
    final keychain = _keychainCredentialsStore;
    if (keychain == null) {
      return;
    }
    try {
      final legacyCredentials = await keychain.readLegacyCredentials();
      if (legacyCredentials == null || legacyCredentials.isEmpty) {
        await keychain.deleteScopedCredentials(runtimeHome.path);
        return;
      }
      await keychain.writeScopedCredentials(
        configDir: runtimeHome.path,
        credentials: legacyCredentials,
      );
    } catch (_) {}
  }

  void _syncLinkedResource({
    required String runtimeHomePath,
    required String entryName,
    required String sourcePath,
  }) {
    final targetPath = p.join(runtimeHomePath, entryName);
    // coverage:ignore-start
    // Source entries come from a just-read directory listing. This handles the
    // filesystem race where an entry disappears before it can be linked.
    if (!_sourceExists(sourcePath)) {
      _removeOwnedRuntimeResource(targetPath, runtimeHomePath, entryName);
      return;
    }
    // coverage:ignore-end
    if (_targetAlreadyPointsToSource(targetPath, sourcePath)) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }

    final targetType = FileSystemEntity.typeSync(
      targetPath,
      followLinks: false,
    );
    String? sourceFingerprint;
    if (targetType != FileSystemEntityType.notFound) {
      final marker = _copiedResourceMarker(runtimeHomePath, entryName);
      final isOwnedFallbackCopy = marker?.sourcePath == sourcePath;
      if (targetType != FileSystemEntityType.link && !isOwnedFallbackCopy) {
        return;
      }
      sourceFingerprint = _resourceFingerprint(sourcePath);
      if (isOwnedFallbackCopy &&
          marker?.sourceFingerprint == sourceFingerprint) {
        return;
      }
      _deleteEntity(targetPath);
    }

    try {
      _resourceLinkCreator(sourcePath: sourcePath, targetPath: targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    } catch (_) {}

    try {
      _deleteEntity(targetPath);
      _copyEntity(sourcePath, targetPath);
      _markCopiedResource(
        runtimeHomePath,
        entryName,
        sourcePath,
        sourceFingerprint ?? _resourceFingerprint(sourcePath),
      );
    } catch (_) {}
  }

  void _removeStaleRuntimeResources(
    Directory runtimeHome,
    Map<String, String> expected,
  ) {
    for (final entity in runtimeHome.listSync(followLinks: false)) {
      final entryName = p.basename(entity.path);
      if (entryName == 'settings.json' ||
          entryName.startsWith('.alera-copied-')) {
        continue;
      }
      final sourcePath = expected[entryName];
      if (sourcePath == null) {
        _removeOwnedRuntimeResource(entity.path, runtimeHome.path, entryName);
        continue;
      }
      if (_targetAlreadyPointsToSource(entity.path, sourcePath) ||
          _targetIsOwnedFallbackCopy(runtimeHome.path, entryName, sourcePath)) {
        continue;
      }
      // coverage:ignore-start
      // _syncLinkedResource handles expected entries before stale cleanup runs.
      // Keep this as a defensive cleanup if that ordering changes.
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        _deleteEntity(entity.path);
        _clearCopiedResourceMarker(runtimeHome.path, entryName);
      }
      // coverage:ignore-end
    }
  }

  void _removeOwnedRuntimeResource(
    String targetPath,
    String runtimeHomePath,
    String entryName,
  ) {
    final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
    // coverage:ignore-start
    // Paired with the disappeared-source race above: clear any stale marker even
    // when the target was already removed by the filesystem or another process.
    if (type == FileSystemEntityType.notFound) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }
    // coverage:ignore-end
    if (type == FileSystemEntityType.link ||
        _copiedResourceMarker(runtimeHomePath, entryName) != null) {
      _deleteEntity(targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
    }
  }

  bool _targetAlreadyPointsToSource(String targetPath, String sourcePath) {
    try {
      final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
      if (type != FileSystemEntityType.link) {
        return false;
      }
      final target = Link(targetPath).targetSync();
      final absoluteTarget = p.isAbsolute(target)
          ? target
          : p.normalize(p.join(p.dirname(targetPath), target));
      return _samePath(absoluteTarget, sourcePath);
    } catch (_) {
      return false;
    }
  }

  bool _targetIsOwnedFallbackCopy(
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    final marker = _copiedResourceMarker(runtimeHomePath, entryName);
    return marker?.sourcePath == sourcePath;
  }

  bool _sourceExists(String sourcePath) {
    return FileSystemEntity.isDirectorySync(sourcePath) ||
        FileSystemEntity.isFileSync(sourcePath) ||
        Link(sourcePath).existsSync();
  }

  _CopiedResourceMarker? _copiedResourceMarker(
    String runtimeHomePath,
    String entryName,
  ) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    if (!marker.existsSync()) {
      return null;
    }
    try {
      final parsed = jsonDecode(marker.readAsStringSync());
      if (parsed is Map && parsed['sourcePath'] is String) {
        return _CopiedResourceMarker(
          sourcePath: parsed['sourcePath'] as String,
          sourceFingerprint: parsed['sourceFingerprint'] is String
              ? parsed['sourceFingerprint'] as String
              : null,
        );
      }
    } catch (_) {}
    return null;
  }

  void _markCopiedResource(
    String runtimeHomePath,
    String entryName,
    String sourcePath,
    String sourceFingerprint,
  ) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync(
      '${jsonEncode(<String, String>{'sourcePath': sourcePath, 'sourceFingerprint': sourceFingerprint})}\n',
    );
  }

  void _clearCopiedResourceMarker(String runtimeHomePath, String entryName) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    if (marker.existsSync()) {
      marker.deleteSync();
    }
  }

  String _copiedResourceMarkerPath(String runtimeHomePath, String entryName) {
    return p.join(runtimeHomePath, '.alera-copied-$entryName.json');
  }

  String _resourceFingerprint(String sourcePath) {
    final records = <Map<String, Object?>>[];
    void collect(String currentPath, String relativePath) {
      final type = FileSystemEntity.typeSync(currentPath, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        final stat = Directory(currentPath).statSync();
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'directory',
          'modified': stat.modified.microsecondsSinceEpoch,
        });
        final children = Directory(currentPath).listSync(followLinks: false)
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
        for (final child in children) {
          final childRelativePath = relativePath.isEmpty
              ? p.basename(child.path)
              : p.join(relativePath, p.basename(child.path));
          collect(child.path, childRelativePath);
        }
        return;
      }
      if (type == FileSystemEntityType.file) {
        final stat = File(currentPath).statSync();
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'file',
          'size': stat.size,
          'modified': stat.modified.microsecondsSinceEpoch,
        });
        return;
      }
      if (type == FileSystemEntityType.link) {
        String? target;
        try {
          target = Link(currentPath).targetSync();
        } catch (_) {}
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'link',
          'target': target,
        });
      }
    }

    collect(sourcePath, '');
    return 'sha256:${sha256.convert(utf8.encode(jsonEncode(records)))}';
  }

  void _copyEntity(String sourcePath, String targetPath) {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      final target = Directory(targetPath)..createSync(recursive: true);
      for (final child in Directory(sourcePath).listSync(followLinks: false)) {
        _copyEntity(child.path, p.join(target.path, p.basename(child.path)));
      }
      return;
    }
    if (type == FileSystemEntityType.file) {
      File(sourcePath).copySync(targetPath);
    }
  }

  void _deleteEntity(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
      return;
    }
    FileSystemEntity.isLinkSync(path)
        ? Link(path).deleteSync()
        : File(path).deleteSync();
  }
}
