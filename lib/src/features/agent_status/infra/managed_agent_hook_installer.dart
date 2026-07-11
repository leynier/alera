import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:path/path.dart' as p;

part 'managed_agent_hook_descriptors.dart';
part 'managed_agent_hook_scripts.dart';
part 'managed_agent_hook_json.dart';

part 'managed_hooks/agy_managed_agent_hook.dart';
part 'managed_hooks/amp_managed_agent_hook.dart';
part 'managed_hooks/claude_managed_agent_hook.dart';
part 'managed_hooks/codex_managed_agent_hook.dart';
part 'managed_hooks/copilot_managed_agent_hook.dart';
part 'managed_hooks/cursor_managed_agent_hook.dart';
part 'managed_hooks/grok_managed_agent_hook.dart';
part 'managed_hooks/opencode_managed_agent_hook.dart';
part 'managed_hooks/pi_managed_agent_hook.dart';

enum ManagedAgentHookInstallState { installed, notInstalled, partial, error }

enum ManagedAgentHookPlatform { posix, windows }

enum _AgentHookConfigShape { hooks, agyBundle }

enum _ManagedHookDefinitionShape {
  nestedCommand,
  directCommand,
  topLevelCommand,
  agyToolCommand,
}

const String _managedArtifactMarker = 'ALERA_AGENT_STATUS_MANAGED_FILE';

class ManagedAgentHookInstallStatus {
  const ManagedAgentHookInstallStatus({
    required this.agentType,
    required this.state,
    required this.configPath,
    required this.managedHooksPresent,
    this.detail,
  });

  final AgentType agentType;
  final ManagedAgentHookInstallState state;
  final String configPath;
  final bool managedHooksPresent;
  final String? detail;
}

class ManagedAgentHookInstallService {
  ManagedAgentHookInstallService({
    String? homeDirectory,
    ManagedAgentHookPlatform? platform,
    Map<String, String>? environment,
  }) : _environment = environment ?? Platform.environment,
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
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _managedArtifactStatus(artifact);
    }
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.error,
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
        state: ManagedAgentHookInstallState.partial,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
        detail: 'Managed Copilot hook file is disabled.',
      );
    }
    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.installed,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: agentType,
      state: ManagedAgentHookInstallState.partial,
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
        state: ManagedAgentHookInstallState.error,
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
      if (managedEvents.contains(entry.key)) {
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
    _setHookContainer(config, descriptor, hooks);
    if (descriptor.agentType == AgentType.copilot) {
      config['version'] = 1;
      config.remove('disableAllHooks');
    }
    if (descriptor.agentType == AgentType.cursor) {
      config['version'] ??= 1;
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
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _removeManagedArtifact(artifact);
    }
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }
    final hooks = _hookContainer(config, descriptor);
    var changed = false;
    for (final entry in hooks.entries.toList(growable: false)) {
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

class _AgentHookDescriptor {
  _AgentHookDescriptor({
    required this.agentType,
    required this.configPath,
    required this.configLabel,
    required this.scriptFileName,
    required this.scriptPath,
    required this.eventEnvVar,
    required this.configShape,
    required this.definitionShape,
    required this.events,
    this.bundleName = 'hooks',
    List<String>? managedScriptFileNames,
    this.windowsWrappers = const <String, String>{},
  }) : managedScriptFileNames =
           managedScriptFileNames ?? <String>[scriptFileName];

  final AgentType agentType;
  final String configPath;
  final String configLabel;
  final String scriptFileName;
  final String scriptPath;
  final String eventEnvVar;
  final _AgentHookConfigShape configShape;
  final _ManagedHookDefinitionShape definitionShape;
  final String bundleName;
  final List<String> managedScriptFileNames;
  final Map<String, String> windowsWrappers;
  final List<_ManagedHookEvent> events;
}

class _ManagedHookArtifact {
  const _ManagedHookArtifact({
    required this.agentType,
    required this.label,
    required this.path,
    required this.content,
  });

  final AgentType agentType;
  final String label;
  final String path;
  final String content;
}

class _ManagedHookEvent {
  const _ManagedHookEvent(this.eventName, {this.matcher, this.definitionShape});

  final String eventName;
  final String? matcher;
  final _ManagedHookDefinitionShape? definitionShape;
}

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
