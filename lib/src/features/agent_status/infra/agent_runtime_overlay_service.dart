import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'agent_runtime_overlay_prepare.dart';
part 'agent_runtime_overlay_wrappers.dart';
part 'agent_runtime_overlay_sources.dart';
part 'agent_runtime_overlay_shell.dart';

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
    bool includeV1Plugin = true,
    bool includeV2Plugin = false,
  }) {
    // v1 and v2 share OPENCODE_CONFIG_DIR. Write only the plugins the user
    // enabled so auto-discovery in either binary does not load the other API.
    final managedFiles = <String, String>{
      if (includeV1Plugin)
        'alera-agent-status.js': aleraOpenCodeStatusPluginSource(),
      if (includeV2Plugin)
        'alera-agent-status-v2.js': aleraOpenCode2StatusPluginSource(),
    };
    if (managedFiles.isEmpty) {
      return Future<AgentRuntimeOverlayPreparation>.value(
        const AgentRuntimeOverlayPreparation(environment: <String, String>{}),
      );
    }
    return _prepareOverlay(
      agentKey: 'opencode',
      terminalSessionId: terminalSessionId,
      publicEnvKey: 'OPENCODE_CONFIG_DIR',
      overlayEnvKey: 'ALERA_OPENCODE_CONFIG_DIR',
      sourceEnvKey: 'ALERA_OPENCODE_SOURCE_CONFIG_DIR',
      defaultSourcePath: _defaultOpenCodeConfigDir(),
      managedSubdirectory: 'plugins',
      managedFiles: managedFiles,
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
      managedFiles: <String, String>{
        'alera-agent-status.ts': aleraPiStatusExtensionSource(),
      },
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
          managedFileNames: const <String>{'alera.json'},
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
        // coverage:ignore-start
        // The overlay is generated under a fresh runtime directory, so install
        // status errors here are filesystem races; fallback behavior is covered
        // through the surrounding catch path.
        throw StateError(status.detail ?? 'Could not install Copilot hooks.');
        // coverage:ignore-end
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
          managedFileNames: const <String>{'alera-agent-status.ts'},
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

String _resolveHome(Map<String, String>? environment) {
  final env = environment ?? Platform.environment;
  // coverage:ignore-start
  // Host-OS branch; injected platform tests cover the Windows overlay paths,
  // while home resolution itself follows the current process platform.
  if (Platform.isWindows) {
    final profile = env['USERPROFILE']?.trim();
    if (profile != null && profile.isNotEmpty) {
      return profile;
    }
  }
  // coverage:ignore-end
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
