part of 'agent_runtime_overlay_service.dart';

extension _AgentRuntimeOverlayWrappers on AgentRuntimeOverlayService {
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
    if (_platform != ManagedAgentHookPlatform.windows && !Platform.isWindows) {
      setPosixFileMode(path, posixExecutableFileMode);
    }
  }

  String _wrapperFileName(String executableName) {
    return _platform == ManagedAgentHookPlatform.windows
        ? '$executableName.cmd'
        : executableName;
  }

  // coverage:ignore-start
  // External command wrapper templates. Overlay tests verify they are selected
  // and written; their runtime behavior is shell/cmd integration coverage.
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

  // coverage:ignore-end
}
