import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
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

  Future<AgentRuntimeOverlayPreparation> prepareCopilotForTerminalLaunch({
    required String terminalSessionId,
  }) async {
    final source = _resolveSource(
      publicEnvKey: 'COPILOT_HOME',
      overlayEnvKey: 'ALERA_COPILOT_HOME',
      sourceEnvKey: 'ALERA_COPILOT_SOURCE_HOME',
      defaultSourcePath: p.join(_homeDirectory, '.copilot'),
    );
    if (source.isExplicit && !_sourceExists(source.path)) {
      return AgentRuntimeOverlayPreparation(
        sourcePath: source.path,
        environment: <String, String>{'COPILOT_HOME': source.path},
      );
    }

    final support = await _applicationSupportDirectory();
    final root = _overlayRoot(support, 'copilot');
    final overlay = _overlayDirectory(root, terminalSessionId);
    try {
      _safeRemoveOverlay(overlay.path, root);
      overlay.createSync(recursive: true);
      if (_sourceExists(source.path)) {
        _mirrorSourceDirectory(
          sourcePath: source.path,
          overlayPath: overlay.path,
          managedSubdirectory: 'hooks',
          managedFileName: 'alera.json',
        );
      }
      final status = ManagedAgentHookInstallService(
        homeDirectory: overlay.path,
        platform: _platform,
        environment: <String, String>{
          ..._environment,
          'HOME': overlay.path,
          'COPILOT_HOME': overlay.path,
        },
      ).install(AgentType.copilot);
      if (status.state == ManagedAgentHookInstallState.error) {
        throw StateError(status.detail ?? 'Could not install Copilot hooks.');
      }
    } catch (_) {
      _safeRemoveOverlay(overlay.path, root);
      if (source.isExplicit) {
        return AgentRuntimeOverlayPreparation(
          sourcePath: source.path,
          environment: <String, String>{'COPILOT_HOME': source.path},
        );
      }
      return const AgentRuntimeOverlayPreparation(
        environment: <String, String>{},
      );
    }

    final sourceExists = _sourceExists(source.path);
    return AgentRuntimeOverlayPreparation(
      overlayPath: overlay.path,
      sourcePath: sourceExists ? source.path : null,
      environment: <String, String>{
        'COPILOT_HOME': overlay.path,
        'ALERA_COPILOT_HOME': overlay.path,
        if (sourceExists) 'ALERA_COPILOT_SOURCE_HOME': source.path,
      },
    );
  }

  Future<AgentRuntimeOverlayPreparation> prepareCursorForTerminalLaunch({
    required String terminalSessionId,
  }) async {
    final support = await _applicationSupportDirectory();
    final root = _overlayRoot(support, 'cursor');
    final overlay = _overlayDirectory(root, terminalSessionId);
    final pluginRoot = Directory(p.join(overlay.path, 'plugin'));
    try {
      _safeRemoveOverlay(overlay.path, root);
      overlay.createSync(recursive: true);
      final status = ManagedAgentHookInstallService(
        homeDirectory: overlay.path,
        platform: _platform,
        environment: <String, String>{..._environment, 'HOME': overlay.path},
      ).install(AgentType.cursor);
      if (status.state == ManagedAgentHookInstallState.error) {
        throw StateError(status.detail ?? 'Could not install Cursor hooks.');
      }
      _writeCursorPlugin(pluginRoot);
      final wrapperBin = _wrapperBinDirectory(support, terminalSessionId);
      _writeAgentWrapper(
        directory: wrapperBin,
        executableName: 'cursor-agent',
        source: _cursorAgentWrapperSource(pluginRoot.path, wrapperBin.path),
      );
      return AgentRuntimeOverlayPreparation(
        overlayPath: overlay.path,
        environment: <String, String>{
          'ALERA_CURSOR_PLUGIN_DIR': pluginRoot.path,
          'ALERA_AGENT_WRAPPER_PATH': wrapperBin.path,
        },
      );
    } catch (_) {
      _safeRemoveOverlay(overlay.path, root);
      return const AgentRuntimeOverlayPreparation(
        environment: <String, String>{},
      );
    }
  }

  Future<AgentRuntimeOverlayPreparation> prepareAmpForTerminalLaunch({
    required String terminalSessionId,
  }) async {
    final source = _resolveAmpSource();
    final support = await _applicationSupportDirectory();
    final root = _overlayRoot(support, 'amp');
    final overlay = _overlayDirectory(root, terminalSessionId);
    final xdgConfigHome = p.join(overlay.path, 'xdg');
    final ampConfigDir = p.join(xdgConfigHome, 'amp');
    try {
      _safeRemoveOverlay(overlay.path, root);
      Directory(ampConfigDir).createSync(recursive: true);
      if (_sourceExists(source.path)) {
        _mirrorSourceDirectory(
          sourcePath: source.path,
          overlayPath: ampConfigDir,
          managedSubdirectory: 'plugins',
          managedFileName: 'alera-agent-status.ts',
        );
      }
      _writeManagedFile(
        p.join(ampConfigDir, 'plugins', 'alera-agent-status.ts'),
        aleraAmpStatusPluginSource(),
      );
      final settingsFile = File(p.join(ampConfigDir, 'settings.json'));
      if (!settingsFile.existsSync()) {
        settingsFile.writeAsStringSync('{}\n');
      }
      final wrapperBin = _wrapperBinDirectory(support, terminalSessionId);
      _writeAgentWrapper(
        directory: wrapperBin,
        executableName: 'amp',
        source: _ampWrapperSource(
          xdgConfigHome: xdgConfigHome,
          settingsFile: settingsFile.path,
          wrapperDirectory: wrapperBin.path,
        ),
      );
      final sourceExists = _sourceExists(source.path);
      return AgentRuntimeOverlayPreparation(
        overlayPath: overlay.path,
        sourcePath: sourceExists ? source.path : null,
        environment: <String, String>{
          'ALERA_AMP_CONFIG_DIR': ampConfigDir,
          if (sourceExists) 'ALERA_AMP_SOURCE_CONFIG_DIR': source.path,
          'ALERA_AGENT_WRAPPER_PATH': wrapperBin.path,
        },
      );
    } catch (_) {
      _safeRemoveOverlay(overlay.path, root);
      return const AgentRuntimeOverlayPreparation(
        environment: <String, String>{},
      );
    }
  }

  Future<void> clearTerminalOverlays(String terminalSessionId) async {
    final support = await _applicationSupportDirectory();
    for (final agentKey in const <String>[
      'opencode',
      'pi',
      'copilot',
      'cursor',
      'amp',
      'wrappers',
    ]) {
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

  void _writeCursorPlugin(Directory pluginRoot) {
    final overlayPath = pluginRoot.parent.path;
    final generatedHooks = File(p.join(overlayPath, '.cursor', 'hooks.json'));
    if (!generatedHooks.existsSync()) {
      throw StateError('Cursor hooks.json was not generated.');
    }
    final pluginHooks = File(p.join(pluginRoot.path, 'hooks', 'hooks.json'));
    pluginHooks.parent.createSync(recursive: true);
    _deleteEntity(pluginHooks.path);
    generatedHooks.copySync(pluginHooks.path);
    _writeJsonObject(
      p.join(pluginRoot.path, '.cursor-plugin', 'plugin.json'),
      <String, Object?>{
        'name': 'alera-agent-status',
        'displayName': 'Alera Agent Status',
        'description': 'Alera terminal agent status hooks.',
        'version': '0.1.0',
        'hooks': 'hooks/hooks.json',
      },
    );
  }

  Directory _wrapperBinDirectory(Directory support, String terminalSessionId) {
    final root = _overlayRoot(support, 'wrappers');
    return Directory(
      p.join(_overlayDirectory(root, terminalSessionId).path, 'bin'),
    );
  }

  void _writeAgentWrapper({
    required Directory directory,
    required String executableName,
    required String source,
  }) {
    final path = p.join(directory.path, _wrapperFileName(executableName));
    _writeManagedFile(path, source);
    if (_platform != ManagedAgentHookPlatform.windows) {
      Process.runSync('chmod', <String>['755', path]);
    }
  }

  String _wrapperFileName(String executableName) {
    return _platform == ManagedAgentHookPlatform.windows
        ? '$executableName.cmd'
        : executableName;
  }

  String _cursorAgentWrapperSource(String pluginRoot, String wrapperDirectory) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return _windowsCursorAgentWrapperSource(pluginRoot);
    }
    return '''#!/bin/sh
${_posixStripWrapperPathPrelude(wrapperDirectory)}
ALERA_PLUGIN_DIR=${_shQuote(pluginRoot)}
ALERA_REAL_COMMAND=\$(command -v cursor-agent 2>/dev/null || true)
if [ -z "\$ALERA_REAL_COMMAND" ]; then
  echo "Alera Cursor wrapper could not find cursor-agent on PATH." >&2
  exit 127
fi
exec "\$ALERA_REAL_COMMAND" --plugin-dir "\$ALERA_PLUGIN_DIR" "\$@"
''';
  }

  String _ampWrapperSource({
    required String xdgConfigHome,
    required String settingsFile,
    required String wrapperDirectory,
  }) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return _windowsAmpWrapperSource(
        xdgConfigHome: xdgConfigHome,
        settingsFile: settingsFile,
      );
    }
    return '''#!/bin/sh
${_posixStripWrapperPathPrelude(wrapperDirectory)}
export XDG_CONFIG_HOME=${_shQuote(xdgConfigHome)}
export AMP_SETTINGS_FILE=${_shQuote(settingsFile)}
ALERA_REAL_COMMAND=\$(command -v amp 2>/dev/null || true)
if [ -z "\$ALERA_REAL_COMMAND" ]; then
  echo "Alera Amp wrapper could not find amp on PATH." >&2
  exit 127
fi
exec "\$ALERA_REAL_COMMAND" "\$@"
''';
  }

  String _posixStripWrapperPathPrelude(String wrapperDirectory) {
    return '''
ALERA_WRAPPER_DIR=${_shQuote(wrapperDirectory)}
ALERA_STRIPPED_PATH=
ALERA_OLD_IFS=\${IFS}
IFS=:
for ALERA_ENTRY in \${PATH:-}; do
  if [ "\$ALERA_ENTRY" = "\$ALERA_WRAPPER_DIR" ]; then
    continue
  fi
  if [ -z "\$ALERA_STRIPPED_PATH" ]; then
    ALERA_STRIPPED_PATH=\$ALERA_ENTRY
  else
    ALERA_STRIPPED_PATH=\$ALERA_STRIPPED_PATH:\$ALERA_ENTRY
  fi
done
IFS=\$ALERA_OLD_IFS
PATH=\$ALERA_STRIPPED_PATH
export PATH
''';
  }

  String _windowsCursorAgentWrapperSource(String pluginRoot) {
    return '''@echo off
setlocal
set "ALERA_PLUGIN_DIR=${_cmdEnvValue(pluginRoot)}"
set "ALERA_REAL_COMMAND="
for /f "delims=" %%P in ('where cursor-agent 2^>nul') do (
  if /I not "%%~fP"=="%~f0" if not defined ALERA_REAL_COMMAND set "ALERA_REAL_COMMAND=%%~fP"
)
if not defined ALERA_REAL_COMMAND (
  echo Alera Cursor wrapper could not find cursor-agent on PATH. 1^>^&2
  exit /b 127
)
"%ALERA_REAL_COMMAND%" --plugin-dir "%ALERA_PLUGIN_DIR%" %*
exit /b %ERRORLEVEL%
''';
  }

  String _windowsAmpWrapperSource({
    required String xdgConfigHome,
    required String settingsFile,
  }) {
    return '''@echo off
setlocal
set "XDG_CONFIG_HOME=${_cmdEnvValue(xdgConfigHome)}"
set "AMP_SETTINGS_FILE=${_cmdEnvValue(settingsFile)}"
set "ALERA_REAL_COMMAND="
for /f "delims=" %%P in ('where amp 2^>nul') do (
  if /I not "%%~fP"=="%~f0" if not defined ALERA_REAL_COMMAND set "ALERA_REAL_COMMAND=%%~fP"
)
if not defined ALERA_REAL_COMMAND (
  echo Alera Amp wrapper could not find amp on PATH. 1^>^&2
  exit /b 127
)
"%ALERA_REAL_COMMAND%" %*
exit /b %ERRORLEVEL%
''';
  }

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

  String _shQuote(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _cmdEnvValue(String value) {
    return value.replaceAll('"', '""');
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
