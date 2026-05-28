part of 'agent_runtime_overlay_service.dart';

extension _AgentRuntimeOverlayWrappers on AgentRuntimeOverlayService {
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
}
