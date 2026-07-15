import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'claude_runtime_resources.dart';
part 'claude_runtime_hooks.dart';

typedef ClaudeApplicationSupportDirectoryResolver =
    Future<Directory> Function();
typedef ClaudeResourceLinkCreator =
    void Function({required String sourcePath, required String targetPath});

abstract interface class ClaudeKeychainCredentialsStore {
  String? readLegacyCredentials();

  void writeScopedCredentials({
    required String configDir,
    required String credentials,
  });

  void deleteScopedCredentials(String configDir);
}

final class ClaudeRuntimeHomePreparation {
  const ClaudeRuntimeHomePreparation({
    required this.runtimeHomePath,
    required this.environment,
    required this.hookStatus,
  });

  final String runtimeHomePath;
  final Map<String, String> environment;
  final ManagedAgentHookInstallStatus hookStatus;
}

final class ClaudeRuntimeHomeService {
  ClaudeRuntimeHomeService({
    String? homeDirectory,
    ClaudeApplicationSupportDirectoryResolver? applicationSupportDirectory,
    ManagedAgentHookPlatform? platform,
    Map<String, String>? environment,
    @visibleForTesting bool syncMacOSKeychainCredentials = true,
    @visibleForTesting ClaudeKeychainCredentialsStore? keychainCredentialsStore,
    @visibleForTesting ClaudeResourceLinkCreator? resourceLinkCreator,
  }) : _environment = environment ?? Platform.environment,
       _homeDirectory = homeDirectory ?? _resolveHome(environment),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _platform =
           platform ??
           (Platform.isWindows
               ? ManagedAgentHookPlatform.windows
               : ManagedAgentHookPlatform.posix),
       _keychainCredentialsStore =
           keychainCredentialsStore ??
           (syncMacOSKeychainCredentials && Platform.isMacOS
               ? const _MacOSClaudeKeychainCredentialsStore()
               : null),
       _resourceLinkCreator = resourceLinkCreator ?? _createResourceLink;

  final Map<String, String> _environment;
  final String _homeDirectory;
  final ClaudeApplicationSupportDirectoryResolver _applicationSupportDirectory;
  final ManagedAgentHookPlatform _platform;
  final ClaudeKeychainCredentialsStore? _keychainCredentialsStore;
  final ClaudeResourceLinkCreator _resourceLinkCreator;

  Future<ClaudeRuntimeHomePreparation> prepareForTerminalLaunch() async {
    final runtimeHome = await _runtimeHomeDirectory();
    final status = await install(runtimeHome: runtimeHome);
    return ClaudeRuntimeHomePreparation(
      runtimeHomePath: runtimeHome.path,
      environment: <String, String>{
        'CLAUDE_CONFIG_DIR': runtimeHome.path,
        'ALERA_CLAUDE_CONFIG_DIR': runtimeHome.path,
      },
      hookStatus: status,
    );
  }

  Future<ManagedAgentHookInstallStatus> status() async {
    final runtimeHome = await _runtimeHomeDirectory();
    final descriptor = _descriptor(runtimeHome);
    final runtimeStatus = _statusForSettings(
      settingsPath: descriptor.settingsPath,
      descriptor: descriptor,
    );
    if (runtimeStatus.state == ManagedAgentHookInstallState.error ||
        runtimeStatus.state == ManagedAgentHookInstallState.notInstalled) {
      return runtimeStatus;
    }

    final incompleteExternal = <String>[];
    for (final settingsPath in _externalClaudeSettingsPaths()) {
      final externalStatus = _statusForSettings(
        settingsPath: settingsPath,
        descriptor: descriptor,
      );
      if (externalStatus.state != ManagedAgentHookInstallState.installed) {
        incompleteExternal.add(settingsPath);
      }
    }
    if (incompleteExternal.isEmpty) {
      return runtimeStatus;
    }
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.claude,
      state: ManagedAgentHookInstallState.partial,
      configPath: runtimeStatus.configPath,
      managedHooksPresent: runtimeStatus.managedHooksPresent,
      detail:
          'Runtime hooks installed, but missing from: '
          '${incompleteExternal.join(', ')}.',
    );
  }

  Future<ManagedAgentHookInstallStatus> install({
    Directory? runtimeHome,
  }) async {
    final runtime = runtimeHome ?? await _runtimeHomeDirectory();
    final source = _sourceConfigDirectory(runtime);
    _syncRuntimeResources(runtime, source);
    _syncKeychainCredentials(runtime);

    final descriptor = _descriptor(runtime);
    final sourceSettingsPath = p.join(source.path, 'settings.json');
    final sourceConfig = _readJsonObject(sourceSettingsPath);
    if (sourceConfig == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: sourceSettingsPath,
        managedHooksPresent: false,
        detail: 'Could not parse Claude settings.json.',
      );
    }

    _writeManagedScript(descriptor.scriptPath, _managedScript());
    final runtimeOk = _installManagedHooksAtSettings(
      settingsPath: descriptor.settingsPath,
      descriptor: descriptor,
      baseConfig: sourceConfig,
    );
    if (!runtimeOk) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.settingsPath,
        managedHooksPresent: false,
        detail: 'Could not write Claude runtime settings.json.',
      );
    }

    // CCS aliases override CLAUDE_CONFIG_DIR to instance homes whose
    // settings.json usually symlinks to ~/.ccs/shared/settings.json.
    for (final settingsPath in _externalClaudeSettingsPaths()) {
      _installManagedHooksAtSettings(
        settingsPath: settingsPath,
        descriptor: descriptor,
      );
    }
    return status();
  }

  Future<ManagedAgentHookInstallStatus> remove() async {
    final runtimeHome = await _runtimeHomeDirectory();
    final descriptor = _descriptor(runtimeHome);
    final runtimeOk = _removeManagedHooksAtSettings(
      settingsPath: descriptor.settingsPath,
      descriptor: descriptor,
    );
    if (!runtimeOk) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.settingsPath,
        managedHooksPresent: false,
        detail: 'Could not parse Claude runtime settings.json.',
      );
    }
    for (final settingsPath in _externalClaudeSettingsPaths()) {
      _removeManagedHooksAtSettings(
        settingsPath: settingsPath,
        descriptor: descriptor,
      );
    }
    return status();
  }
}

void _createResourceLink({
  required String sourcePath,
  required String targetPath,
}) {
  Link(targetPath).createSync(sourcePath);
}

// coverage:ignore-start
// Native macOS keychain adapter. Service behavior is covered through
// ClaudeKeychainCredentialsStore fakes; exercising this class would mutate the
// developer keychain and depend on the local `security` binary.
final class _MacOSClaudeKeychainCredentialsStore
    implements ClaudeKeychainCredentialsStore {
  const _MacOSClaudeKeychainCredentialsStore();

  static const String _legacyService = 'Claude Code-credentials';

  @override
  String? readLegacyCredentials() {
    return _readPassword(_legacyService);
  }

  @override
  void writeScopedCredentials({
    required String configDir,
    required String credentials,
  }) {
    _runSecurity(<String>[
      'add-generic-password',
      '-U',
      '-s',
      _scopedService(configDir),
      '-a',
      _keychainUser(),
      '-w',
      credentials,
    ]);
  }

  @override
  void deleteScopedCredentials(String configDir) {
    _runSecurity(<String>[
      'delete-generic-password',
      '-s',
      _scopedService(configDir),
      '-a',
      _keychainUser(),
    ], ignoreNotFound: true);
  }

  String? _readPassword(String service) {
    final result = Process.runSync('security', <String>[
      'find-generic-password',
      '-s',
      service,
      '-a',
      _keychainUser(),
      '-w',
    ]);
    if (result.exitCode == 0) {
      final password = (result.stdout as String).trim();
      return password.isEmpty ? null : password;
    }
    if (_isSecurityNotFound(result)) {
      return null;
    }
    throw const FileSystemException('Could not read Claude credentials.');
  }

  void _runSecurity(List<String> arguments, {bool ignoreNotFound = false}) {
    final result = Process.runSync('security', arguments);
    if (result.exitCode == 0) {
      return;
    }
    if (ignoreNotFound && _isSecurityNotFound(result)) {
      return;
    }
    throw const FileSystemException('Could not update Claude credentials.');
  }

  bool _isSecurityNotFound(ProcessResult result) {
    final output = '${result.stdout} ${result.stderr}'.toLowerCase();
    return result.exitCode == 44 ||
        output.contains('could not be found') ||
        output.contains('not be found');
  }

  String _scopedService(String configDir) {
    final suffix = sha256
        .convert(utf8.encode(configDir))
        .toString()
        .substring(0, 8);
    return '$_legacyService-$suffix';
  }

  String _keychainUser() {
    final user =
        Platform.environment['USER'] ?? Platform.environment['USERNAME'];
    if (user == null || user.trim().isEmpty) {
      return 'user';
    }
    return user;
  }
}
// coverage:ignore-end

class _ClaudeRuntimeHookDescriptor {
  const _ClaudeRuntimeHookDescriptor({
    required this.settingsPath,
    required this.scriptPath,
    required this.managedScriptFileNames,
  });

  final String settingsPath;
  final String scriptPath;
  final Set<String> managedScriptFileNames;
}

class _ClaudeHookEvent {
  const _ClaudeHookEvent(this.eventName, {this.matcher});

  final String eventName;
  final String? matcher;
}

class _CopiedResourceMarker {
  const _CopiedResourceMarker({
    required this.sourcePath,
    required this.sourceFingerprint,
  });

  final String sourcePath;
  final String? sourceFingerprint;
}

const List<_ClaudeHookEvent> _claudeEvents = <_ClaudeHookEvent>[
  _ClaudeHookEvent('UserPromptSubmit'),
  _ClaudeHookEvent('Stop'),
  _ClaudeHookEvent('PreToolUse', matcher: '*'),
  _ClaudeHookEvent('PostToolUse', matcher: '*'),
  _ClaudeHookEvent('PostToolUseFailure', matcher: '*'),
  _ClaudeHookEvent('PermissionRequest', matcher: '*'),
];

String _shQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _resolveHome(Map<String, String>? environment) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null || home.trim().isEmpty) {
    throw StateError('Could not resolve the user home directory.');
  }
  return home;
}
