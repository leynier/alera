import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:path/path.dart' as p;

part 'managed_agent_hook_descriptors.dart';
part 'managed_agent_hook_scripts.dart';
part 'managed_agent_hook_json.dart';

part 'managed_hooks/agy_managed_agent_hook.dart';
part 'managed_hooks/amp_managed_agent_hook.dart';
part 'managed_hooks/claude_managed_agent_hook.dart';
part 'managed_hooks/codex_managed_agent_hook.dart';
part 'managed_hooks/copilot_managed_agent_hook.dart';
part 'managed_hooks/grok_managed_agent_hook.dart';
part 'managed_hooks/opencode_managed_agent_hook.dart';
part 'managed_hooks/opencode2_managed_agent_hook.dart';
part 'managed_hooks/pi_managed_agent_hook.dart';

enum ManagedAgentHookInstallState { installed, notInstalled, partial, error }

enum ManagedAgentHookPlatform { posix, windows }

enum _AgentHookConfigShape { hooks, agyBundle }

enum _ManagedHookDefinitionShape {
  nestedCommand,
  directCommand,
  topLevelCommand,

  /// Antigravity lifecycle hooks: `[{ "type": "command", "command": "..." }]`.
  agyLifecycleCommand,

  /// Antigravity tool hooks: `[{ "matcher": "*", "hooks": [{ "type": "command", ... }] }]`.
  agyToolCommand,
}

const String _managedArtifactMarker = 'ALERA_AGENT_STATUS_MANAGED_FILE';

class const ManagedAgentHookInstallStatus({
  required final AgentType agentType,
  required final ManagedAgentHookInstallState state,
  required final String configPath,
  required final bool managedHooksPresent,
  final String? detail,
});

class ManagedAgentHookInstallService({
  String? homeDirectory,
  ManagedAgentHookPlatform? platform,
  Map<String, String>? environment,
}) {
  this
    : _environment = environment ?? Platform.environment,
      _homeDirectory = homeDirectory ?? _resolveHome(environment),
      _platform =
          platform ??
          (Platform.isWindows
              ? ManagedAgentHookPlatform.windows
              : ManagedAgentHookPlatform.posix);

  final Map<String, String> _environment;
  final String _homeDirectory;
  final ManagedAgentHookPlatform _platform;

  ManagedAgentHookInstallStatus status(AgentType agentType) {
    if (agentType == AgentType.codex) {
      return _codexRuntimeOnlyStatus();
    }
    if (agentType == AgentType.claude) {
      return _claudeRuntimeOnlyStatus();
    }
    if (agentType == AgentType.cursor) {
      return _cursorRuntimeOnlyStatus();
    }
    if (agentType == AgentType.fx) {
      return _fxRuntimeOnlyStatus();
    }
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _managedArtifactStatus(artifact);
    }
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }
    final missing = <String>[];
    var presentCount = 0;
    final hooks = _hookContainer(config, descriptor);
    for (final event in descriptor.events) {
      final command = _managedCommand(descriptor: descriptor, event: event);
      final definitions = _definitionsFromValue(hooks[event.eventName]);
      final hasCommand = definitions.any(
        (definition) => _definitionHasCommand(definition, command),
      );
      if (hasCommand) {
        presentCount += 1;
      } else {
        missing.add(event.eventName);
      }
    }
    final managedHooksPresent = presentCount > 0;
    if (descriptor.agentType == AgentType.copilot &&
        config['disableAllHooks'] == true &&
        managedHooksPresent) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .partial,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
        detail: 'Managed Copilot hook file is disabled.',
      );
    }
    // Antigravity's `enabled: false` disables a whole bundle without removing
    // it, so the handlers can be present and still never run.
    if (descriptor.configShape == _AgentHookConfigShape.agyBundle &&
        hooks['enabled'] == false &&
        managedHooksPresent) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .partial,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
        detail: 'Managed Antigravity hook bundle is disabled.',
      );
    }
    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .notInstalled,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .installed,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: agentType,
      state: .partial,
      configPath: descriptor.configPath,
      managedHooksPresent: managedHooksPresent,
      detail: 'Managed hook missing for events: ${missing.join(', ')}.',
    );
  }

  ManagedAgentHookInstallStatus install(AgentType agentType) {
    if (agentType == AgentType.codex) {
      return _codexRuntimeOnlyStatus();
    }
    if (agentType == AgentType.claude) {
      return _claudeRuntimeOnlyStatus();
    }
    if (agentType == AgentType.cursor) {
      return _cursorRuntimeOnlyStatus();
    }
    if (agentType == AgentType.fx) {
      return _fxRuntimeOnlyStatus();
    }
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      final current = _managedArtifactStatus(artifact);
      if (current.state == ManagedAgentHookInstallState.error) {
        return current;
      }
      _writeManagedArtifact(artifact);
      return _managedArtifactStatus(artifact);
    }
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }

    final hooks = _hookContainer(config, descriptor);
    final managedEvents = descriptor.events
        .map((event) => event.eventName)
        .toSet();
    for (final entry in hooks.entries.toList(growable: false)) {
      if (managedEvents.contains(entry.key) || entry.value is! List) {
        continue;
      }
      final definitions = _definitionsFromValue(entry.value);
      final cleaned = _removeManagedCommands(
        definitions,
        descriptor.managedScriptFileNames,
      );
      if (cleaned.isEmpty) {
        hooks.remove(entry.key);
      } else {
        hooks[entry.key] = cleaned;
      }
    }
    for (final event in descriptor.events) {
      final current = _definitionsFromValue(hooks[event.eventName]);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.managedScriptFileNames,
      );
      final definition = _managedHookDefinition(
        descriptor,
        event,
        _managedCommand(descriptor: descriptor, event: event),
      );
      hooks[event.eventName] = <Object?>[...cleaned, definition];
    }
    // Installing is an explicit request to enable, so Antigravity's documented
    // `enabled: false` opt-out cannot survive it.
    if (descriptor.configShape == _AgentHookConfigShape.agyBundle) {
      hooks.remove('enabled');
    }
    _setHookContainer(config, descriptor, hooks);
    if (descriptor.agentType == AgentType.copilot) {
      config['version'] = 1;
      config.remove('disableAllHooks');
    }
    _writeManagedScript(
      descriptor.scriptPath,
      _managedScript(descriptor: descriptor),
    );
    for (final wrapper in descriptor.windowsWrappers.entries) {
      _writeManagedScript(wrapper.key, wrapper.value);
    }
    _writeJsonObject(descriptor.configPath, config);
    return status(agentType);
  }

  ManagedAgentHookInstallStatus remove(AgentType agentType) {
    if (agentType == AgentType.codex) {
      return _codexRuntimeOnlyStatus();
    }
    if (agentType == AgentType.claude) {
      return _claudeRuntimeOnlyStatus();
    }
    if (agentType == AgentType.cursor) {
      return _cursorRuntimeOnlyStatus();
    }
    if (agentType == AgentType.fx) {
      return _fxRuntimeOnlyStatus();
    }
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _removeManagedArtifact(artifact);
    }
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: .error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }
    final hooks = _hookContainer(config, descriptor);
    var changed = false;
    for (final entry in hooks.entries.toList(growable: false)) {
      // Non-event keys such as Antigravity's `enabled` flag are not handler
      // lists; dropping them here would silently rewrite the user's config.
      if (entry.value is! List) {
        continue;
      }
      final definitions = _definitionsFromValue(entry.value);
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
    // `enabled` alone is not a hook set, so an emptied Alera bundle should not
    // survive as leftover config.
    if (descriptor.configShape == _AgentHookConfigShape.agyBundle &&
        hooks.keys.every((key) => key == 'enabled')) {
      hooks.clear();
    }
    if (changed) {
      _setHookContainer(config, descriptor, hooks);
      _writeJsonObject(descriptor.configPath, config);
    }
    return status(agentType);
  }

  Future<List<ManagedAgentHookInstallStatus>> installAll() async {
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values) install(agentType),
    ];
  }

  Future<List<ManagedAgentHookInstallStatus>> removeAll() async {
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values) remove(agentType),
    ];
  }

  Future<List<ManagedAgentHookInstallStatus>> reconcile({
    required Iterable<AgentType> enabledAgentTypes,
    Iterable<AgentType>? agentTypes,
  }) async {
    final enabled = enabledAgentTypes.toSet();
    final candidates = agentTypes ?? AgentType.values;
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in candidates)
        enabled.contains(agentType) ? install(agentType) : remove(agentType),
    ];
  }
}

class _AgentHookDescriptor({
  required final AgentType agentType,
  required final String configPath,
  required final String configLabel,
  required final String scriptFileName,
  required final String scriptPath,
  required final String eventEnvVar,
  required final _AgentHookConfigShape configShape,
  required final _ManagedHookDefinitionShape definitionShape,
  required final List<_ManagedHookEvent> events,
  final String bundleName = 'hooks',
  List<String>? managedScriptFileNames,
  final Map<String, String> windowsWrappers = const <String, String>{},
}) {
  this
    : managedScriptFileNames =
          managedScriptFileNames ?? <String>[scriptFileName];

  final List<String> managedScriptFileNames;
}

class const _ManagedHookArtifact({
  required final AgentType agentType,
  required final String label,
  required final String path,
  required final String content,
});

class const _ManagedHookEvent(
  final String eventName, {
  final String? matcher,
  final _ManagedHookDefinitionShape? definitionShape,
});

String _shQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _powerShellSingleQuote(String value) => value.replaceAll("'", "''");

String _powerShellPath(String value) => "'${_powerShellSingleQuote(value)}'";

String _resolveHome(Map<String, String>? environment) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null || home.trim().isEmpty) {
    throw StateError('Could not resolve the user home directory.');
  }
  return home;
}
