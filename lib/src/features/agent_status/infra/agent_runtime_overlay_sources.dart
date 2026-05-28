part of 'agent_runtime_overlay_service.dart';

extension _AgentRuntimeOverlaySources on AgentRuntimeOverlayService {
  _OverlaySource _resolveAmpSource() {
    final sourceValue = _trimmedEnvironmentValue('ALERA_AMP_SOURCE_CONFIG_DIR');
    if (sourceValue != null) {
      return _OverlaySource(sourceValue, isExplicit: true);
    }

    final ampConfigValue = _trimmedEnvironmentValue('AMP_CONFIG_DIR');
    final overlayValue = _trimmedEnvironmentValue('ALERA_AMP_CONFIG_DIR');
    if (ampConfigValue != null &&
        (overlayValue == null || !_samePath(ampConfigValue, overlayValue))) {
      return _OverlaySource(ampConfigValue, isExplicit: true);
    }

    final xdgConfigHome = _trimmedEnvironmentValue('XDG_CONFIG_HOME');
    if (xdgConfigHome != null) {
      final candidate = p.join(xdgConfigHome, 'amp');
      if (overlayValue == null || !_samePath(candidate, overlayValue)) {
        return _OverlaySource(candidate, isExplicit: false);
      }
    }

    return _OverlaySource(_defaultAmpConfigDir(), isExplicit: false);
  }

  _OverlaySource _resolveSource({
    required String publicEnvKey,
    required String overlayEnvKey,
    required String sourceEnvKey,
    required String defaultSourcePath,
  }) {
    final sourceValue = _trimmedEnvironmentValue(sourceEnvKey);
    if (sourceValue != null) {
      return _OverlaySource(sourceValue, isExplicit: true);
    }

    final publicValue = _trimmedEnvironmentValue(publicEnvKey);
    final overlayValue = _trimmedEnvironmentValue(overlayEnvKey);
    if (publicValue != null &&
        (overlayValue == null || !_samePath(publicValue, overlayValue))) {
      return _OverlaySource(publicValue, isExplicit: true);
    }

    final startupValue = _readShellStartupEnvVar(publicEnvKey);
    if (startupValue != null) {
      return _OverlaySource(startupValue, isExplicit: true);
    }

    return _OverlaySource(defaultSourcePath, isExplicit: false);
  }

  String? _trimmedEnvironmentValue(String key) {
    final value = _environment[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _defaultOpenCodeConfigDir() {
    if (_platform == ManagedAgentHookPlatform.windows) {
      final appData = _trimmedEnvironmentValue('APPDATA');
      if (appData != null) {
        return p.join(appData, 'opencode');
      }
    }
    return p.join(_homeDirectory, '.config', 'opencode');
  }

  String _defaultAmpConfigDir() {
    if (_platform == ManagedAgentHookPlatform.windows) {
      final userProfile = _trimmedEnvironmentValue('USERPROFILE');
      if (userProfile != null) {
        return p.join(userProfile, '.config', 'amp');
      }
    }
    return p.join(_homeDirectory, '.config', 'amp');
  }

  String _overlayRoot(Directory support, String agentKey) {
    return p.join(support.path, 'agent-runtime-overlays', agentKey);
  }

  Directory _overlayDirectory(String root, String terminalSessionId) {
    final hash = sha256
        .convert(utf8.encode(terminalSessionId))
        .toString()
        .substring(0, 32);
    return Directory(p.join(root, hash));
  }

  void _mirrorSourceDirectory({
    required String sourcePath,
    required String overlayPath,
    required String managedSubdirectory,
    required String managedFileName,
  }) {
    for (final entry in Directory(sourcePath).listSync(followLinks: false)) {
      final entryName = p.basename(entry.path);
      if (entryName == managedSubdirectory && _isDirectoryLike(entry.path)) {
        final targetDirectory = p.join(overlayPath, managedSubdirectory);
        Directory(targetDirectory).createSync(recursive: true);
        for (final child in Directory(
          entry.path,
        ).listSync(followLinks: false)) {
          final childName = p.basename(child.path);
          if (childName == managedFileName) {
            continue;
          }
          _mirrorEntry(
            child.path,
            p.join(targetDirectory, childName),
            overlayPath,
          );
        }
        continue;
      }
      _mirrorEntry(entry.path, p.join(overlayPath, entryName), overlayPath);
    }
  }

  void _mirrorEntry(String sourcePath, String targetPath, String overlayPath) {
    try {
      _resourceLinkCreator(sourcePath: sourcePath, targetPath: targetPath);
      return;
    } catch (_) {}

    _copyEntity(sourcePath, targetPath);
    _markCopiedResource(overlayPath, targetPath, sourcePath);
  }

  void _writeManagedFile(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    _deleteEntity(path);
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(content);
    tmp.renameSync(path);
  }

  void _writeJsonObject(String path, Map<String, Object?> value) {
    _writeManagedFile(
      path,
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    );
  }

  void _copyEntity(String sourcePath, String targetPath) {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      Directory(targetPath).createSync(recursive: true);
      for (final child in Directory(sourcePath).listSync(followLinks: false)) {
        _copyEntity(child.path, p.join(targetPath, p.basename(child.path)));
      }
      return;
    }
    if (type == FileSystemEntityType.file) {
      File(sourcePath).copySync(targetPath);
      return;
    }
    if (FileSystemEntity.typeSync(sourcePath, followLinks: false) ==
        FileSystemEntityType.link) {
      final target = Link(sourcePath).targetSync();
      Link(targetPath).createSync(target, recursive: true);
    }
  }

  void _markCopiedResource(
    String overlayPath,
    String targetPath,
    String sourcePath,
  ) {
    final relative = p.relative(targetPath, from: overlayPath);
    final encoded = base64Url.encode(utf8.encode(relative));
    final marker = File(
      p.join(overlayPath, '.alera-copied-resources', '$encoded.json'),
    );
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync(
      '${jsonEncode(<String, String>{'sourcePath': sourcePath, 'targetPath': targetPath})}\n',
    );
  }

  void _safeRemoveOverlay(String overlayPath, String overlayRoot) {
    final resolvedRoot = p.normalize(p.absolute(overlayRoot));
    final resolvedTarget = p.normalize(p.absolute(overlayPath));
    final relative = p.relative(resolvedTarget, from: resolvedRoot);
    if (relative == '.' ||
        relative.startsWith('..') ||
        p.isAbsolute(relative)) {
      return;
    }
    _safeRemoveTree(resolvedTarget);
  }

  void _safeRemoveTree(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type != FileSystemEntityType.directory) {
      _deleteEntity(path);
      return;
    }
    for (final child in Directory(path).listSync(followLinks: false)) {
      _safeRemoveTree(child.path);
    }
    try {
      Directory(path).deleteSync();
    } catch (_) {}
  }

  void _deleteEntity(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    try {
      if (type == FileSystemEntityType.directory &&
          !FileSystemEntity.isLinkSync(path)) {
        Directory(path).deleteSync(recursive: true);
      } else if (FileSystemEntity.isLinkSync(path)) {
        Link(path).deleteSync();
      } else {
        File(path).deleteSync();
      }
    } catch (_) {}
  }

  bool _sourceExists(String path) {
    return FileSystemEntity.isDirectorySync(path) ||
        FileSystemEntity.isFileSync(path) ||
        Link(path).existsSync();
  }

  bool _isDirectoryLike(String path) {
    return FileSystemEntity.isDirectorySync(path);
  }

  bool _samePath(String left, String right) {
    return p.normalize(p.absolute(left)) == p.normalize(p.absolute(right));
  }
}
