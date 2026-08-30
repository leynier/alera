import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'codex_runtime_resource_sync.dart';
part 'codex_runtime_config_sync.dart';
part 'codex_runtime_hook_planning.dart';
part 'codex_runtime_io.dart';
part 'codex_runtime_hook_config.dart';
part 'codex_runtime_trust_hash.dart';
part 'codex_runtime_text_files.dart';
part 'codex_runtime_toml.dart';

typedef CodexApplicationSupportDirectoryResolver = Future<Directory> Function();
typedef CodexResourceLinkCreator = void Function({
  required String sourcePath,
  required String targetPath,
});

final class CodexRuntimeHomePreparation {
  const CodexRuntimeHomePreparation({
    required this.runtimeHomePath,
    required this.environment,
    required this.hookStatus,
  });

  final String runtimeHomePath;
  final Map<String, String> environment;
  final ManagedAgentHookInstallStatus hookStatus;
}

final class CodexRuntimeHomeService {
  CodexRuntimeHomeService({
    String? homeDirectory,
    CodexApplicationSupportDirectoryResolver? applicationSupportDirectory,
    ManagedAgentHookPlatform? platform,
    Map<String, String>? environment,
    @visibleForTesting CodexResourceLinkCreator? resourceLinkCreator,
  }) : _homeDirectory = homeDirectory ?? _resolveHome(environment),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _platform =
           platform ??
           (Platform.isWindows
               ? ManagedAgentHookPlatform.windows
               : ManagedAgentHookPlatform.posix),
       _resourceLinkCreator = resourceLinkCreator ?? _createResourceLink;

  final String _homeDirectory;
  final CodexApplicationSupportDirectoryResolver _applicationSupportDirectory;
  final ManagedAgentHookPlatform _platform;
  final CodexResourceLinkCreator _resourceLinkCreator;

  Future<CodexRuntimeHomePreparation> prepareForTerminalLaunch() async {
    final runtimeHome = await _runtimeHomeDirectory();
    _syncAuth(runtimeHome);
    _syncSystemResources(runtimeHome);
    _syncSystemConfig(runtimeHome);
    _syncSystemSessions(runtimeHome);
    final status = await install();
    return CodexRuntimeHomePreparation(
      runtimeHomePath: runtimeHome.path,
      environment: <String, String>{
        'CODEX_HOME': runtimeHome.path,
        'ALERA_CODEX_HOME': runtimeHome.path,
      },
      hookStatus: status,
    );
  }

  Future<ManagedAgentHookInstallStatus> status() async {
    final descriptor = await _descriptor();
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse Codex runtime hooks.json.',
      );
    }

    final trustEntries = _readHookTrustEntries(descriptor.tomlPath);
    final hooks = _hooksMap(config);
    var presentCount = 0;
    final missing = <String>[];
    final trustMissing = <String>[];
    final disabled = <String>[];
    for (final eventName in _codexEvents) {
      final command = _managedCommand(descriptor.scriptPath, eventName);
      final definitions = _definitionsFromValue(hooks[eventName]);
      var foundGroupIndex = -1;
      var foundHandlerIndex = -1;
      for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
        final definition = definitions[groupIndex];
        final handlers = _hookHandlers(definition);
        for (
          var handlerIndex = 0;
          handlerIndex < handlers.length;
          handlerIndex++
        ) {
          if (handlers[handlerIndex]['command'] == command) {
            foundGroupIndex = groupIndex;
            foundHandlerIndex = handlerIndex;
          }
        }
      }
      if (foundGroupIndex < 0) {
        missing.add(eventName);
        continue;
      }
      presentCount += 1;
      final trustEntry = _CodexHookTrustEntry(
        sourcePath: descriptor.configPath,
        eventLabel: _codexEventLabel(eventName),
        groupIndex: foundGroupIndex,
        handlerIndex: foundHandlerIndex,
        command: command,
      );
      final state = trustEntries[_computeTrustKey(trustEntry)];
      if (state?.trustedHash != _computeTrustedHash(trustEntry)) {
        trustMissing.add(eventName);
      } else if (state?.enabled == false) {
        disabled.add(eventName);
      }
    }

    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty && trustMissing.isEmpty && disabled.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.installed,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
      );
    }
    final details = <String>[
      if (missing.isNotEmpty)
        'Managed hook missing for events: ${missing.join(', ')}.',
      if (trustMissing.isNotEmpty)
        'Trust entry missing for events: ${trustMissing.join(', ')}.',
      if (disabled.isNotEmpty)
        'Managed hook disabled for events: ${disabled.join(', ')}.',
    ];
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.codex,
      state: ManagedAgentHookInstallState.partial,
      configPath: descriptor.configPath,
      managedHooksPresent: true,
      detail: details.join(' '),
    );
  }

  Future<ManagedAgentHookInstallStatus> install() async {
    final runtimeHome = await _runtimeHomeDirectory();
    _syncAuth(runtimeHome);
    _syncSystemResources(runtimeHome);
    _syncSystemConfig(runtimeHome);
    _syncSystemSessions(runtimeHome);

    final descriptor = await _descriptor(runtimeHome: runtimeHome);
    final runtimeConfig = _readJsonObject(descriptor.configPath);
    if (runtimeConfig == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse Codex runtime hooks.json.',
      );
    }

    final plan = _runtimeHooksWithSystemUserHooks(descriptor);
    final nextHooks = plan.hooks;
    final trustEntries = <_CodexHookTrustEntry>[
      for (final mirrored in plan.trustEntries) mirrored.entry,
    ];
    for (final eventName in _codexEvents) {
      final command = _managedCommand(descriptor.scriptPath, eventName);
      final current = _definitionsFromValue(nextHooks[eventName]);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.managedScriptFileNames,
      );
      final definition = <String, Object?>{
        'hooks': <Object?>[
          <String, Object?>{'type': 'command', 'command': command},
        ],
      };
      nextHooks[eventName] = <Object?>[...cleaned, definition];
      trustEntries.add(
        _CodexHookTrustEntry(
          sourcePath: descriptor.configPath,
          eventLabel: _codexEventLabel(eventName),
          groupIndex: cleaned.length,
          handlerIndex: 0,
          command: command,
        ),
      );
    }

    runtimeConfig['hooks'] = nextHooks;
    _writeManagedScript(descriptor.scriptPath, _managedScript());
    _writeJsonObject(descriptor.configPath, runtimeConfig);
    _syncSystemConfig(runtimeHome);
    _removeStaleRuntimeTrustEntries(
      tomlPath: descriptor.tomlPath,
      runtimeHooksPath: descriptor.configPath,
      expectedEntries: trustEntries,
    );
    _upsertHookTrustEntries(
      descriptor.tomlPath,
      trustEntries.map(
        (entry) => _MirroredRuntimeUserHookTrustEntry(entry, true),
      ),
    );
    _upsertHookTrustEntries(descriptor.tomlPath, plan.trustEntries);
    return status();
  }

  Future<ManagedAgentHookInstallStatus> remove() async {
    final descriptor = await _descriptor();
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse Codex runtime hooks.json.',
      );
    }
    final hooks = _hooksMap(config);
    final trustEntries = <_CodexHookTrustEntry>[];
    var changed = false;
    for (final entry in hooks.entries.toList(growable: false)) {
      final definitions = _definitionsFromValue(entry.value);
      trustEntries.addAll(
        _collectManagedTrustEntries(
          sourcePath: descriptor.configPath,
          eventName: entry.key,
          definitions: definitions,
          managedScriptFileNames: descriptor.managedScriptFileNames,
        ),
      );
      final cleaned = _removeManagedCommands(
        definitions,
        descriptor.managedScriptFileNames,
      );
      if (jsonEncode(cleaned) != jsonEncode(definitions)) {
        changed = true;
      }
      if (cleaned.isEmpty) {
        hooks.remove(entry.key);
      } else {
        hooks[entry.key] = cleaned;
      }
    }
    if (changed) {
      config['hooks'] = hooks;
      _writeJsonObject(descriptor.configPath, config);
    }
    _removeMatchingTrustEntries(descriptor.tomlPath, trustEntries);
    return status();
  }

  Future<Directory> _runtimeHomeDirectory() async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'agent-runtime-homes', 'codex', 'home'),
    );
    directory.createSync(recursive: true);
    return directory;
  }

  Future<_CodexRuntimeHookDescriptor> _descriptor({
    Directory? runtimeHome,
  }) async {
    final runtime = runtimeHome ?? await _runtimeHomeDirectory();
    final extension = switch (_platform) {
      ManagedAgentHookPlatform.posix => 'sh',
      ManagedAgentHookPlatform.windows => 'cmd',
    };
    final scriptFileName = 'alera-codex-hook.$extension';
    return _CodexRuntimeHookDescriptor(
      configPath: p.join(runtime.path, 'hooks.json'),
      tomlPath: p.join(runtime.path, 'config.toml'),
      systemConfigPath: p.join(_systemHomePath, 'hooks.json'),
      systemTomlPath: p.join(_systemHomePath, 'config.toml'),
      scriptPath: p.join(
        _homeDirectory,
        '.alera',
        'agent-hooks',
        scriptFileName,
      ),
      managedScriptFileNames: <String>{scriptFileName},
    );
  }
}

const List<String> _codexEvents = <String>[
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PermissionRequest',
  'PostToolUse',
  'Stop',
];

const List<String> _codexSystemResourceEntries = <String>[
  'skills',
  'plugins',
  'plugin-state',
  'profile-v2',
  'themes',
  'prompts',
];

const List<String> _codexPluginOnlyHookPlaceholders = <String>[
  r'${CLAUDE_PLUGIN_ROOT}',
  r'${CLAUDE_PLUGIN_DATA}',
  r'${PLUGIN_ROOT}',
  r'${PLUGIN_DATA}',
];

const Map<String, String> _codexEventLabels = <String, String>{
  'SessionStart': 'session_start',
  'UserPromptSubmit': 'user_prompt_submit',
  'PreToolUse': 'pre_tool_use',
  'PermissionRequest': 'permission_request',
  'PostToolUse': 'post_tool_use',
  'Stop': 'stop',
  'PreCompact': 'pre_compact',
  'PostCompact': 'post_compact',
};

String _codexEventLabel(String eventName) => _codexEventLabels[eventName]!;

final class _CodexRuntimeHookDescriptor {
  const _CodexRuntimeHookDescriptor({
    required this.configPath,
    required this.tomlPath,
    required this.systemConfigPath,
    required this.systemTomlPath,
    required this.scriptPath,
    required this.managedScriptFileNames,
  });

  final String configPath;
  final String tomlPath;
  final String systemConfigPath;
  final String systemTomlPath;
  final String scriptPath;
  final Set<String> managedScriptFileNames;
}

final class _RuntimeHookPlan {
  const _RuntimeHookPlan(this.hooks, this.trustEntries);

  final Map<String, Object?> hooks;
  final List<_MirroredRuntimeUserHookTrustEntry> trustEntries;
}

final class _CodexHookTrustEntry {
  const _CodexHookTrustEntry({
    required this.sourcePath,
    required this.eventLabel,
    required this.groupIndex,
    required this.handlerIndex,
    required this.command,
    this.timeoutSec,
    this.async,
    this.matcher,
    this.statusMessage,
  });

  final String sourcePath;
  final String eventLabel;
  final int groupIndex;
  final int handlerIndex;
  final String command;
  final int? timeoutSec;
  final bool? async;
  final String? matcher;
  final String? statusMessage;
}

final class _CodexHookTrustState {
  const _CodexHookTrustState({this.trustedHash, this.enabled});

  final String? trustedHash;
  final bool? enabled;
}

final class _ParsedTrustKey {
  const _ParsedTrustKey({required this.sourcePath, required this.eventLabel});

  final String sourcePath;
  final String eventLabel;
}

final class _MirroredRuntimeUserHookTrustEntry {
  const _MirroredRuntimeUserHookTrustEntry(this.entry, this.enabled);

  final _CodexHookTrustEntry entry;
  final bool enabled;
}

final class _CopiedResourceMarker {
  const _CopiedResourceMarker({
    required this.sourcePath,
    required this.sourceFingerprint,
  });

  final String sourcePath;
  final String? sourceFingerprint;
}
