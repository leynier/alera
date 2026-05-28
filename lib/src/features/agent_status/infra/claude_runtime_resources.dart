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

  void _syncKeychainCredentials(Directory runtimeHome) {
    final keychain = _keychainCredentialsStore;
    if (keychain == null) {
      return;
    }
    try {
      final legacyCredentials = keychain.readLegacyCredentials();
      if (legacyCredentials == null || legacyCredentials.isEmpty) {
        keychain.deleteScopedCredentials(runtimeHome.path);
        return;
      }
      keychain.writeScopedCredentials(
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
    if (!_sourceExists(sourcePath)) {
      _removeOwnedRuntimeResource(targetPath, runtimeHomePath, entryName);
      return;
    }
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
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        _deleteEntity(entity.path);
        _clearCopiedResourceMarker(runtimeHome.path, entryName);
      }
    }
  }

  void _removeOwnedRuntimeResource(
    String targetPath,
    String runtimeHomePath,
    String entryName,
  ) {
    final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }
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
