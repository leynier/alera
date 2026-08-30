part of 'codex_runtime_home_service.dart';

extension _CodexRuntimeHomeServiceResourceSync on CodexRuntimeHomeService {
  String get _systemHomePath => p.join(_homeDirectory, '.codex');

  void _syncAuth(Directory runtimeHome) {
    final source = File(p.join(_systemHomePath, 'auth.json'));
    final target = File(p.join(runtimeHome.path, 'auth.json'));
    if (!source.existsSync()) {
      _deleteEntity(target.path);
      return;
    }
    if (target.existsSync()) {
      final sourceStat = source.statSync();
      final targetStat = target.statSync();
      if (!sourceStat.modified.isAfter(targetStat.modified) &&
          target.readAsStringSync() != '') {
        return;
      }
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    if (_platform == ManagedAgentHookPlatform.posix && !Platform.isWindows) {
      setPosixFileMode(target.path, posixPrivateFileMode);
    }
  }

  void _syncSystemResources(Directory runtimeHome) {
    for (final entryName in _codexSystemResourceEntries) {
      _syncLinkedResource(
        systemHomePath: _systemHomePath,
        runtimeHomePath: runtimeHome.path,
        entryName: entryName,
        allowCopyFallback: true,
      );
    }
  }

  void _syncSystemSessions(Directory runtimeHome) {
    _syncLinkedResource(
      systemHomePath: _systemHomePath,
      runtimeHomePath: runtimeHome.path,
      entryName: 'sessions',
      allowCopyFallback: false,
    );
  }

  void _syncLinkedResource({
    required String systemHomePath,
    required String runtimeHomePath,
    required String entryName,
    required bool allowCopyFallback,
  }) {
    final sourcePath = p.join(systemHomePath, entryName);
    final targetPath = p.join(runtimeHomePath, entryName);
    if (!FileSystemEntity.isDirectorySync(sourcePath) &&
        !FileSystemEntity.isFileSync(sourcePath) &&
        !Link(sourcePath).existsSync()) {
      _removeOwnedRuntimeResource(
        targetPath,
        runtimeHomePath,
        entryName,
        sourcePath,
      );
      return;
    }
    if (_targetAlreadyPointsToSource(targetPath, sourcePath)) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }
    final targetExists =
        FileSystemEntity.typeSync(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound;
    String? sourceFingerprint;
    if (targetExists) {
      final marker = _copiedResourceMarker(runtimeHomePath, entryName);
      final isOwnedFallbackCopy = marker?.sourcePath == sourcePath;
      if (!isOwnedFallbackCopy) {
        return;
      }
      sourceFingerprint = _resourceFingerprint(sourcePath);
      if (marker?.sourceFingerprint == sourceFingerprint) {
        return;
      }
      _deleteEntity(targetPath);
    }
    try {
      _resourceLinkCreator(sourcePath: sourcePath, targetPath: targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    } catch (_) {
      if (!allowCopyFallback) {
        return;
      }
    }
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

  void _removeOwnedRuntimeResource(
    String targetPath,
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    if (_targetAlreadyPointsToSource(targetPath, sourcePath) ||
        _targetIsOwnedFallbackCopy(
          targetPath,
          runtimeHomePath,
          entryName,
          sourcePath,
        )) {
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
      return p.normalize(absoluteTarget) == p.normalize(sourcePath);
    } catch (_) {
      return false;
    }
  }

  bool _targetIsOwnedFallbackCopy(
    String targetPath,
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    if (FileSystemEntity.typeSync(targetPath, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return false;
    }
    final marker = _copiedResourceMarker(runtimeHomePath, entryName);
    return marker?.sourcePath == sourcePath;
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
          // Persist the same precision as markers written before Dart 3.13.
          'modified':
              stat.modified.millisecondsSinceEpoch *
              Duration.microsecondsPerMillisecond,
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
          'modified':
              stat.modified.millisecondsSinceEpoch *
              Duration.microsecondsPerMillisecond,
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
        return;
      }
      // coverage:ignore-start
      // Defensive handling for uncommon FileSystemEntityType values; normal
      // directory, file, and link fingerprints are covered with real entries.
      records.add(<String, Object?>{
        'path': relativePath,
        'type': _fileSystemEntityTypeName(type),
      });
      // coverage:ignore-end
    }

    collect(sourcePath, '');
    final serialized = jsonEncode(_canonicalize(records));
    return 'sha256:${sha256.convert(utf8.encode(serialized))}';
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
