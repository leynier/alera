import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AgentOverlayApplicationSupportDirectoryResolver =
    Future<Directory> Function();
typedef AgentOverlayResourceLinkCreator =
    void Function({required String sourcePath, required String targetPath});

final class AgentRuntimeOverlayPreparation {
  const AgentRuntimeOverlayPreparation({
    required this.environment,
    this.overlayPath,
    this.sourcePath,
  });

  final Map<String, String> environment;
  final String? overlayPath;
  final String? sourcePath;
}

final class AgentRuntimeOverlayService {
  AgentRuntimeOverlayService({
    String? homeDirectory,
    ManagedAgentHookPlatform? platform,
    Map<String, String>? environment,
    AgentOverlayApplicationSupportDirectoryResolver?
    applicationSupportDirectory,
    @visibleForTesting AgentOverlayResourceLinkCreator? resourceLinkCreator,
  }) : _environment = environment ?? Platform.environment,
       _homeDirectory = homeDirectory ?? _resolveHome(environment),
       _platform =
           platform ??
           (Platform.isWindows
               ? ManagedAgentHookPlatform.windows
               : ManagedAgentHookPlatform.posix),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _resourceLinkCreator = resourceLinkCreator ?? _createResourceLink;

  final Map<String, String> _environment;
  final String _homeDirectory;
  final ManagedAgentHookPlatform _platform;
  final AgentOverlayApplicationSupportDirectoryResolver
  _applicationSupportDirectory;
  final AgentOverlayResourceLinkCreator _resourceLinkCreator;

  Future<AgentRuntimeOverlayPreparation> prepareOpenCodeForTerminalLaunch({
    required String terminalSessionId,
  }) {
    return _prepareOverlay(
      agentKey: 'opencode',
      terminalSessionId: terminalSessionId,
      publicEnvKey: 'OPENCODE_CONFIG_DIR',
      overlayEnvKey: 'ALERA_OPENCODE_CONFIG_DIR',
      sourceEnvKey: 'ALERA_OPENCODE_SOURCE_CONFIG_DIR',
      defaultSourcePath: _defaultOpenCodeConfigDir(),
      managedSubdirectory: 'plugins',
      managedFileName: 'alera-agent-status.js',
      managedFileContent: aleraOpenCodeStatusPluginSource(),
    );
  }

  Future<AgentRuntimeOverlayPreparation> preparePiForTerminalLaunch({
    required String terminalSessionId,
  }) {
    return _prepareOverlay(
      agentKey: 'pi',
      terminalSessionId: terminalSessionId,
      publicEnvKey: 'PI_CODING_AGENT_DIR',
      overlayEnvKey: 'ALERA_PI_CODING_AGENT_DIR',
      sourceEnvKey: 'ALERA_PI_SOURCE_AGENT_DIR',
      defaultSourcePath: p.join(_homeDirectory, '.pi', 'agent'),
      managedSubdirectory: 'extensions',
      managedFileName: 'alera-agent-status.ts',
      managedFileContent: aleraPiStatusExtensionSource(),
    );
  }

  Future<void> clearTerminalOverlays(String terminalSessionId) async {
    final support = await _applicationSupportDirectory();
    for (final agentKey in const <String>['opencode', 'pi']) {
      final root = _overlayRoot(support, agentKey);
      _safeRemoveOverlay(_overlayDirectory(root, terminalSessionId).path, root);
    }
  }

  Future<AgentRuntimeOverlayPreparation> _prepareOverlay({
    required String agentKey,
    required String terminalSessionId,
    required String publicEnvKey,
    required String overlayEnvKey,
    required String sourceEnvKey,
    required String defaultSourcePath,
    required String managedSubdirectory,
    required String managedFileName,
    required String managedFileContent,
  }) async {
    final source = _resolveSource(
      publicEnvKey: publicEnvKey,
      overlayEnvKey: overlayEnvKey,
      sourceEnvKey: sourceEnvKey,
      defaultSourcePath: defaultSourcePath,
    );
    if (source.isExplicit && !_sourceExists(source.path)) {
      return AgentRuntimeOverlayPreparation(
        sourcePath: source.path,
        environment: <String, String>{publicEnvKey: source.path},
      );
    }

    final support = await _applicationSupportDirectory();
    final root = _overlayRoot(support, agentKey);
    final overlay = _overlayDirectory(root, terminalSessionId);
    try {
      _safeRemoveOverlay(overlay.path, root);
      overlay.createSync(recursive: true);
      if (_sourceExists(source.path)) {
        _mirrorSourceDirectory(
          sourcePath: source.path,
          overlayPath: overlay.path,
          managedSubdirectory: managedSubdirectory,
          managedFileName: managedFileName,
        );
      }
      _writeManagedFile(
        p.join(overlay.path, managedSubdirectory, managedFileName),
        managedFileContent,
      );
    } catch (_) {
      _safeRemoveOverlay(overlay.path, root);
      if (source.isExplicit) {
        return AgentRuntimeOverlayPreparation(
          sourcePath: source.path,
          environment: <String, String>{publicEnvKey: source.path},
        );
      }
      return const AgentRuntimeOverlayPreparation(
        environment: <String, String>{},
      );
    }

    return AgentRuntimeOverlayPreparation(
      overlayPath: overlay.path,
      sourcePath: _sourceExists(source.path) ? source.path : null,
      environment: <String, String>{
        publicEnvKey: overlay.path,
        overlayEnvKey: overlay.path,
        if (_sourceExists(source.path)) sourceEnvKey: source.path,
      },
    );
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

  String? _readShellStartupEnvVar(String name) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return null;
    }
    final shell = _trimmedEnvironmentValue('SHELL');
    final paths = _shellStartupFilePaths(shell);
    String? last;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      try {
        final match = _parseExportedValue(file.readAsStringSync(), name);
        if (match != null) {
          last = match;
        }
      } catch (_) {}
    }
    return last;
  }

  List<String> _shellStartupFilePaths(String? shell) {
    final name = shell?.replaceAll(r'\', '/').split('/').last.toLowerCase();
    if (name == null || name == 'zsh') {
      final zshEnvPath = p.join(_homeDirectory, '.zshenv');
      final zshEnv = File(zshEnvPath).existsSync()
          ? File(zshEnvPath).readAsStringSync()
          : '';
      final zdotdir = _parseExportedValue(zshEnv, 'ZDOTDIR') ?? _homeDirectory;
      return <String>[
        zshEnvPath,
        for (final file in const <String>['.zprofile', '.zshrc', '.zlogin'])
          p.join(zdotdir, file),
      ];
    }
    if (name == 'bash') {
      return <String>[
        p.join(_homeDirectory, '.bash_profile'),
        p.join(_homeDirectory, '.bash_login'),
        p.join(_homeDirectory, '.profile'),
        p.join(_homeDirectory, '.bashrc'),
      ];
    }
    return const <String>[];
  }

  String? _parseExportedValue(String content, String name) {
    final assignment = RegExp('^export\\s+$name=(.+)\$');
    String? last;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final match = assignment.firstMatch(rawLine.trim());
      if (match == null) {
        continue;
      }
      final decommented = _stripTrailingComment(match.group(1) ?? '');
      final unquoted = _unquoteShellValue(decommented.trim());
      final expanded = unquoted.quoted == "'"
          ? unquoted.text
          : _expandHome(unquoted.text);
      if (expanded.isNotEmpty) {
        last = expanded;
      }
    }
    return last;
  }

  _ShellValue _unquoteShellValue(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return _ShellValue(value.substring(1, value.length - 1), value[0]);
    }
    return _ShellValue(value, null);
  }

  String _stripTrailingComment(String value) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < value.length; i += 1) {
      final ch = value[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (ch == '#' && !inSingle && !inDouble) {
        final previous = i == 0 ? null : value[i - 1];
        if (previous == null || previous == ' ' || previous == '\t') {
          return value.substring(0, i).trimRight();
        }
      }
    }
    return value;
  }

  String _expandHome(String value) {
    return value
        .replaceFirst(RegExp(r'^~(?=$|/)'), _homeDirectory)
        .replaceAll(r'${HOME}', _homeDirectory)
        .replaceAll(RegExp(r'\$HOME(?![A-Za-z0-9_])'), _homeDirectory);
  }

  static String _resolveHome(Map<String, String>? environment) {
    final env = environment ?? Platform.environment;
    if (Platform.isWindows) {
      final profile = env['USERPROFILE']?.trim();
      if (profile != null && profile.isNotEmpty) {
        return profile;
      }
    }
    final home = env['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return home;
    }
    final profile = env['USERPROFILE']?.trim();
    if (profile != null && profile.isNotEmpty) {
      return profile;
    }
    return Directory.current.path;
  }
}

final class _OverlaySource {
  const _OverlaySource(this.path, {required this.isExplicit});

  final String path;
  final bool isExplicit;
}

final class _ShellValue {
  const _ShellValue(this.text, this.quoted);

  final String text;
  final String? quoted;
}

void _createResourceLink({
  required String sourcePath,
  required String targetPath,
}) {
  Link(targetPath).createSync(sourcePath, recursive: true);
}
