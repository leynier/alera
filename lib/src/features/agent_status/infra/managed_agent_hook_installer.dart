import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:path/path.dart' as p;

enum ManagedAgentHookInstallState { installed, notInstalled, partial, error }

enum ManagedAgentHookPlatform { posix, windows }

enum _AgentHookConfigShape { hooks, agyBundle }

enum _ManagedHookDefinitionShape {
  nestedCommand,
  directCommand,
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
  }) async {
    final enabled = enabledAgentTypes.toSet();
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values)
        enabled.contains(agentType) ? install(agentType) : remove(agentType),
    ];
  }

  _AgentHookDescriptor _descriptor(AgentType agentType) {
    final extension = switch ((agentType, _platform)) {
      (AgentType.copilot, ManagedAgentHookPlatform.windows) => 'ps1',
      (_, ManagedAgentHookPlatform.windows) => 'cmd',
      (_, ManagedAgentHookPlatform.posix) => 'sh',
    };
    final scriptFileName = 'alera-${agentType.key}-hook.$extension';
    final scriptPath = p.join(
      _homeDirectory,
      '.alera',
      'agent-hooks',
      scriptFileName,
    );
    return switch (agentType) {
      AgentType.codex => _AgentHookDescriptor(
        agentType: agentType,
        configPath: p.join(_homeDirectory, '.codex', 'hooks.json'),
        configLabel: 'Codex hooks.json',
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
        eventEnvVar: 'ALERA_AGENT_HOOK_EVENT',
        configShape: _AgentHookConfigShape.hooks,
        definitionShape: _ManagedHookDefinitionShape.nestedCommand,
        events: const <_ManagedHookEvent>[
          _ManagedHookEvent('SessionStart'),
          _ManagedHookEvent('UserPromptSubmit'),
          _ManagedHookEvent('PreToolUse'),
          _ManagedHookEvent('PostToolUse'),
          _ManagedHookEvent('PermissionRequest'),
          _ManagedHookEvent('Stop'),
        ],
      ),
      AgentType.claude => _AgentHookDescriptor(
        agentType: agentType,
        configPath: p.join(_homeDirectory, '.claude', 'settings.json'),
        configLabel: 'Claude settings.json',
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
        eventEnvVar: 'ALERA_AGENT_HOOK_EVENT',
        configShape: _AgentHookConfigShape.hooks,
        definitionShape: _ManagedHookDefinitionShape.nestedCommand,
        events: const <_ManagedHookEvent>[
          _ManagedHookEvent('UserPromptSubmit'),
          _ManagedHookEvent('Stop'),
          _ManagedHookEvent('PreToolUse', matcher: '*'),
          _ManagedHookEvent('PostToolUse', matcher: '*'),
          _ManagedHookEvent('PostToolUseFailure', matcher: '*'),
          _ManagedHookEvent('PermissionRequest', matcher: '*'),
        ],
      ),
      AgentType.copilot => _AgentHookDescriptor(
        agentType: agentType,
        configPath: p.join(_copilotHome(), 'hooks', 'alera.json'),
        configLabel: 'Copilot hooks/alera.json',
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
        eventEnvVar: 'ALERA_COPILOT_HOOK_EVENT',
        configShape: _AgentHookConfigShape.hooks,
        definitionShape: _ManagedHookDefinitionShape.directCommand,
        events: const <_ManagedHookEvent>[
          _ManagedHookEvent('SessionStart'),
          _ManagedHookEvent('SessionEnd'),
          _ManagedHookEvent('UserPromptSubmit'),
          _ManagedHookEvent('PreToolUse'),
          _ManagedHookEvent('PostToolUse'),
          _ManagedHookEvent('PostToolUseFailure'),
          _ManagedHookEvent('subagentStart'),
          _ManagedHookEvent('SubagentStop'),
          _ManagedHookEvent('PreCompact'),
          _ManagedHookEvent('Stop'),
          _ManagedHookEvent('ErrorOccurred'),
          _ManagedHookEvent('PermissionRequest'),
          _ManagedHookEvent('Notification'),
        ],
      ),
      AgentType.agy => _agyDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.opencode || AgentType.pi => throw ArgumentError.value(
        agentType,
        'agentType',
        'Managed artifact agents do not use JSON hook descriptors.',
      ),
    };
  }

  _AgentHookDescriptor _agyDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    final events = const <_ManagedHookEvent>[
      _ManagedHookEvent('PreInvocation'),
      _ManagedHookEvent('PostInvocation'),
      _ManagedHookEvent('Stop'),
      _ManagedHookEvent(
        'PostToolUse',
        matcher: '*',
        definitionShape: _ManagedHookDefinitionShape.agyToolCommand,
      ),
    ];
    final wrappers = <String, String>{};
    if (_platform == ManagedAgentHookPlatform.windows) {
      for (final event in events) {
        final path = _agyWindowsWrapperPath(event.eventName);
        wrappers[path] = _agyWindowsWrapperScript(event.eventName);
      }
    }
    return _AgentHookDescriptor(
      agentType: AgentType.agy,
      configPath: p.join(_homeDirectory, '.gemini', 'config', 'hooks.json'),
      configLabel: 'Antigravity hooks.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_AGY_EVENT',
      configShape: _AgentHookConfigShape.agyBundle,
      definitionShape: _ManagedHookDefinitionShape.nestedCommand,
      bundleName: 'alera-status',
      managedScriptFileNames: <String>[
        scriptFileName,
        if (_platform == ManagedAgentHookPlatform.windows)
          for (final event in events)
            p.basename(_agyWindowsWrapperPath(event.eventName)),
      ],
      windowsWrappers: wrappers,
      events: events,
    );
  }

  String _copilotHome() {
    final fromEnv = _environment['COPILOT_HOME']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return p.join(_homeDirectory, '.copilot');
  }

  _ManagedHookArtifact? _managedArtifact(AgentType agentType) {
    return switch (agentType) {
      AgentType.opencode => _ManagedHookArtifact(
        agentType: agentType,
        label: 'OpenCode status plugin',
        path: p.join(_opencodeConfigDir(), 'plugins', 'alera-agent-status.js'),
        content: _opencodePluginSource(),
      ),
      AgentType.pi => _ManagedHookArtifact(
        agentType: agentType,
        label: 'Pi status extension',
        path: p.join(_piAgentDir(), 'extensions', 'alera-agent-status.ts'),
        content: _piExtensionSource(),
      ),
      AgentType.codex ||
      AgentType.claude ||
      AgentType.copilot ||
      AgentType.agy => null,
    };
  }

  String _opencodeConfigDir() {
    final fromEnv = _environment['OPENCODE_CONFIG_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (_platform == ManagedAgentHookPlatform.windows) {
      final appData = _environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'opencode');
      }
    }
    return p.join(_homeDirectory, '.config', 'opencode');
  }

  String _piAgentDir() {
    final fromEnv = _environment['PI_CODING_AGENT_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return p.join(_homeDirectory, '.pi', 'agent');
  }

  ManagedAgentHookInstallStatus _managedArtifactStatus(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: artifact.path,
        managedHooksPresent: false,
      );
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Rename it before enabling this hook.',
      );
    }
    if (content == artifact.content) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.installed,
        configPath: artifact.path,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: artifact.agentType,
      state: ManagedAgentHookInstallState.partial,
      configPath: artifact.path,
      managedHooksPresent: true,
      detail: 'Managed ${artifact.label} needs to be updated.',
    );
  }

  ManagedAgentHookInstallStatus _removeManagedArtifact(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return _managedArtifactStatus(artifact);
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Refusing to remove it.',
      );
    }
    file.deleteSync();
    return _managedArtifactStatus(artifact);
  }

  void _writeManagedArtifact(_ManagedHookArtifact artifact) {
    final file = File(artifact.path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == artifact.content) {
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(artifact.content);
    tmp.renameSync(artifact.path);
  }

  String _opencodePluginSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
let warnedBadEndpoint = false;
let cachedEndpointKey = "";
let cachedEndpointValues = null;
let lastStatus = "idle";
const childSessionById = new Map();
const messageRoleById = new Map();

function readEndpointFile() {
  const path = process.env.ALERA_AGENT_HOOK_ENDPOINT;
  if (!path) return null;
  try {
    const fs = require("fs");
    try {
      const stat = fs.statSync(path);
      const cacheKey = stat.mtimeMs + ":" + stat.size + ":" + stat.ino;
      if (cacheKey === cachedEndpointKey && cachedEndpointValues) {
        return cachedEndpointValues;
      }
      const contents = fs.readFileSync(path, "utf8");
      const out = {};
      for (const line of contents.split(/\r?\n/)) {
        const m = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/);
        if (m) out[m[1]] = m[2].replace(/\r$/, "");
      }
      cachedEndpointKey = cacheKey;
      cachedEndpointValues = out;
      return out;
    } catch (ioErr) {
      cachedEndpointKey = "";
      cachedEndpointValues = null;
      throw ioErr;
    }
  } catch (err) {
    if (err && err.code !== "ENOENT" && !warnedBadEndpoint) {
      warnedBadEndpoint = true;
      console.warn("[alera-opencode-status] failed to parse endpoint file:", err.message);
    }
    return null;
  }
}

function resolveHookCoords() {
  const fileEnv = readEndpointFile() || {};
  return {
    port: fileEnv.ALERA_AGENT_HOOK_PORT || process.env.ALERA_AGENT_HOOK_PORT,
    token: fileEnv.ALERA_AGENT_HOOK_TOKEN || process.env.ALERA_AGENT_HOOK_TOKEN,
    version: fileEnv.ALERA_AGENT_HOOK_VERSION || process.env.ALERA_AGENT_HOOK_VERSION || "",
  };
}

function getStatusType(event) {
  return event?.properties?.status?.type ?? event?.status?.type ?? null;
}

function rememberMessageRole(messageID, role) {
  if (!messageID || !role) return;
  if (messageRoleById.size >= 128) {
    const first = messageRoleById.keys().next().value;
    if (first !== undefined) messageRoleById.delete(first);
  }
  messageRoleById.set(messageID, role);
}

async function isChildSession(client, sessionID) {
  if (!sessionID) return false;
  if (childSessionById.has(sessionID)) return childSessionById.get(sessionID);
  if (!client?.session?.list) return false;
  try {
    const sessions = await Promise.race([
      client.session.list(),
      new Promise((_, reject) => setTimeout(() => reject(new Error("session.list timeout")), 250)),
    ]);
    const list = Array.isArray(sessions?.data) ? sessions.data : [];
    const session = list.find((entry) => entry?.id === sessionID);
    const isChild = !!session?.parentID;
    if (childSessionById.size >= 128) {
      const first = childSessionById.keys().next().value;
      if (first !== undefined) childSessionById.delete(first);
    }
    childSessionById.set(sessionID, isChild);
    return isChild;
  } catch {
    return false;
  }
}

function isStatusEvent(event) {
  return event.type === "permission.asked" ||
    event.type === "question.asked" ||
    event.type === "message.updated" ||
    event.type === "message.part.updated" ||
    event.type === "session.idle" ||
    event.type === "session.error" ||
    event.type === "session.status";
}

async function post(hookEventName, extraProperties) {
  const coords = resolveHookCoords();
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID;
  const workspaceId = process.env.ALERA_WORKSPACE_ID;
  const tabId = process.env.ALERA_TAB_ID;
  if (!coords.port || !coords.token || !terminalSessionId || !workspaceId || !tabId) return;
  const url = `http://127.0.0.1:${coords.port}/hook/opencode`;
  const body = JSON.stringify({
    terminalSessionId,
    workspaceId,
    tabId,
    version: coords.version,
    payload: { hook_event_name: hookEventName, ...(extraProperties || {}) },
  });
  try {
    const options = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Alera-Agent-Hook-Token": coords.token,
      },
      body,
    };
    if (typeof AbortSignal !== "undefined" && AbortSignal.timeout) {
      options.signal = AbortSignal.timeout(1000);
    }
    await fetch(url, options);
  } catch {}
}

async function setStatus(next, extraProperties) {
  if (lastStatus === next) return;
  lastStatus = next;
  await post(next === "busy" ? "SessionBusy" : "SessionIdle", extraProperties);
}

export const AleraOpenCodeStatusPlugin = async (_ctx) => {
  const client = _ctx?.client;
  return {
    event: async ({ event }) => {
      if (!event?.type) return;

      if (event.type === "message.updated") {
        const info = event.properties && event.properties.info;
        rememberMessageRole(info && info.id, info && info.role);
      }

      if (!isStatusEvent(event)) {
        return;
      }

      if (event.type === "permission.asked") {
        await post("PermissionRequest", event.properties || {});
        return;
      }

      if (event.type === "question.asked") {
        await post("AskUserQuestion", event.properties || {});
        return;
      }

      if (event.type === "message.updated") {
        return;
      }

      if (event.type === "message.part.updated") {
        const part = event.properties && event.properties.part;
        if (!part || part.type !== "text" || !part.text) return;
        const role = messageRoleById.get(part.messageID);
        if (!role) return;
        await post("MessagePart", { role, text: part.text });
        return;
      }

      if (event.type === "session.idle" || event.type === "session.error") {
        await setStatus("idle");
        return;
      }

      if (event.type === "session.status") {
        const statusType = getStatusType(event);
        if (statusType === "busy" || statusType === "retry") {
          await setStatus("busy");
          return;
        }
        if (statusType === "idle") {
          await setStatus("idle");
        }
      }
    },
  };
};
''';

  String _piExtensionSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
let warnedBadEndpoint = false
let cachedEndpointKey = ''
let cachedEndpointValues = null

function readEndpointFile() {
  const path = process.env.ALERA_AGENT_HOOK_ENDPOINT
  if (!path) return null
  try {
    const fs = require('fs')
    try {
      const stat = fs.statSync(path)
      const cacheKey = stat.mtimeMs + ':' + stat.size + ':' + stat.ino
      if (cacheKey === cachedEndpointKey && cachedEndpointValues) {
        return cachedEndpointValues
      }
      const contents = fs.readFileSync(path, 'utf8')
      const out = {}
      for (const line of contents.split(/\r?\n/)) {
        const m = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/)
        if (m) out[m[1]] = m[2].replace(/\r$/, '')
      }
      cachedEndpointKey = cacheKey
      cachedEndpointValues = out
      return out
    } catch (ioErr) {
      cachedEndpointKey = ''
      cachedEndpointValues = null
      throw ioErr
    }
  } catch (err) {
    if (err && err.code !== 'ENOENT' && !warnedBadEndpoint) {
      warnedBadEndpoint = true
      console.warn('[alera-pi-status] failed to parse endpoint file:', err.message)
    }
    return null
  }
}

function resolveHookCoords() {
  const fileEnv = readEndpointFile() || {}
  return {
    port: fileEnv.ALERA_AGENT_HOOK_PORT || process.env.ALERA_AGENT_HOOK_PORT,
    token: fileEnv.ALERA_AGENT_HOOK_TOKEN || process.env.ALERA_AGENT_HOOK_TOKEN,
    version: fileEnv.ALERA_AGENT_HOOK_VERSION || process.env.ALERA_AGENT_HOOK_VERSION || '',
  }
}

async function post(hookEventName, extra = {}) {
  const coords = resolveHookCoords()
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!coords.port || !coords.token || !terminalSessionId || !workspaceId || !tabId) return
  const url = `http://127.0.0.1:${coords.port}/hook/pi`
  const body = JSON.stringify({
    terminalSessionId,
    workspaceId,
    tabId,
    version: coords.version,
    payload: { hook_event_name: hookEventName, ...extra },
  })
  try {
    const options = {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Alera-Agent-Hook-Token': coords.token,
      },
      body,
    }
    if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) {
      options.signal = AbortSignal.timeout(1000)
    }
    await fetch(url, options)
  } catch {}
}

function extractAssistantText(message) {
  if (!message || typeof message !== 'object') return ''
  const content = message.content
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  let out = ''
  for (const part of content) {
    if (part && typeof part === 'object' && part.type === 'text' && typeof part.text === 'string') {
      out += part.text
    }
  }
  return out
}

export default function (pi) {
  pi.on('before_agent_start', async (event) => {
    await post('before_agent_start', { prompt: event.prompt ?? '' })
  })

  pi.on('agent_start', async () => {
    await post('agent_start')
  })

  pi.on('tool_execution_start', async (event) => {
    await post('tool_execution_start', {
      tool_name: event.toolName,
      tool_input: event.args,
    })
  })

  pi.on('tool_call', async (event) => {
    await post('tool_call', {
      tool_name: event.toolName,
      tool_input: event.input,
    })
  })

  pi.on('tool_execution_end', async (event) => {
    await post('tool_execution_end', {
      tool_name: event.toolName,
    })
  })

  pi.on('message_end', async (event) => {
    if (event.message?.role !== 'assistant') return
    const text = extractAssistantText(event.message)
    if (!text) return
    await post('message_end', { role: 'assistant', text })
  })

  pi.on('agent_end', async () => {
    await post('agent_end')
  })

  pi.on('session_shutdown', async () => {
    await post('session_shutdown')
  })
}
''';

  String _managedCommand({
    required _AgentHookDescriptor descriptor,
    required _ManagedHookEvent event,
  }) {
    if (descriptor.agentType == AgentType.agy &&
        _platform == ManagedAgentHookPlatform.windows) {
      return _agyWindowsWrapperPath(event.eventName);
    }
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(descriptor.scriptPath)} ]; then '
            '${descriptor.eventEnvVar}=${_shQuote(event.eventName)} '
            '/bin/sh ${_shQuote(descriptor.scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        descriptor.agentType == AgentType.copilot
            ? '\$env:${descriptor.eventEnvVar} = \'${_powerShellSingleQuote(event.eventName)}\'; '
                  'powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
                  '${_powerShellPath(descriptor.scriptPath)}'
            : 'cmd /d /s /c "if exist ""${descriptor.scriptPath}"" '
                  '(set ${descriptor.eventEnvVar}=${event.eventName}&& call ""${descriptor.scriptPath}"")"',
    };
  }

  String _managedScript({required _AgentHookDescriptor descriptor}) {
    final source = descriptor.agentType.key;
    if (descriptor.agentType == AgentType.agy) {
      return _agyManagedScript(descriptor);
    }
    final eventEnvVar = descriptor.eventEnvVar;
    if (_platform == ManagedAgentHookPlatform.windows) {
      if (descriptor.agentType == AgentType.copilot) {
        return _windowsPowerShellManagedScript(
          source: source,
          eventEnvVar: eventEnvVar,
          writeEmptyResponse: true,
        );
      }
      return <String>[
        '@echo off',
        'setlocal',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(source, eventEnvVar),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
      if (descriptor.agentType == AgentType.copilot) "printf '{}\\n'",
      'if [ -n "\$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -r "\$ALERA_AGENT_HOOK_ENDPOINT" ]; then',
      '  . "\$ALERA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :',
      'fi',
      'if [ -z "\$ALERA_AGENT_HOOK_PORT" ] || [ -z "\$ALERA_AGENT_HOOK_TOKEN" ] || [ -z "\$ALERA_TERMINAL_SESSION_ID" ] || [ -z "\$ALERA_WORKSPACE_ID" ] || [ -z "\$ALERA_TAB_ID" ]; then',
      '  exit 0',
      'fi',
      'payload=\$(cat)',
      'if [ -z "\$payload" ]; then',
      '  exit 0',
      'fi',
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/$source" \\',
      '  -H "Content-Type: application/x-www-form-urlencoded" \\',
      '  -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '  --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '  --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '  --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '  --data-urlencode "hookEventName=\${$eventEnvVar}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _windowsPostCommand(String source, String eventEnvVar) {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:$eventEnvVar; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/$source\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
  }

  Map<String, Object?> _managedHookDefinition(
    _AgentHookDescriptor descriptor,
    _ManagedHookEvent event,
    String command,
  ) {
    final shape = event.definitionShape ?? descriptor.definitionShape;
    return switch (shape) {
      _ManagedHookDefinitionShape.nestedCommand => <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{'type': 'command', 'command': command},
        ],
      },
      _ManagedHookDefinitionShape.directCommand => <String, Object?>{
        'type': 'command',
        if (_platform == ManagedAgentHookPlatform.windows)
          'powershell': command
        else
          'bash': command,
        'timeoutSec': 5,
      },
      _ManagedHookDefinitionShape.agyToolCommand => <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{'type': 'command', 'command': command},
        ],
      },
    };
  }

  Map<String, Object?> _hookContainer(
    Map<String, Object?> config,
    _AgentHookDescriptor descriptor,
  ) {
    return switch (descriptor.configShape) {
      _AgentHookConfigShape.hooks => _hooksMap(config),
      _AgentHookConfigShape.agyBundle => _mapFromValue(
        config[descriptor.bundleName],
      ),
    };
  }

  void _setHookContainer(
    Map<String, Object?> config,
    _AgentHookDescriptor descriptor,
    Map<String, Object?> hooks,
  ) {
    switch (descriptor.configShape) {
      case _AgentHookConfigShape.hooks:
        config['hooks'] = hooks;
      case _AgentHookConfigShape.agyBundle:
        if (hooks.isEmpty) {
          config.remove(descriptor.bundleName);
        } else {
          config[descriptor.bundleName] = hooks;
        }
    }
  }

  Map<String, Object?>? _readJsonObject(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is Map) {
        return Map<String, Object?>.from(parsed);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _writeJsonObject(String path, Map<String, Object?> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final serialized =
        '${const JsonEncoder.withIndent('  ').convert(config)}\n';
    if (file.existsSync() && file.readAsStringSync() == serialized) {
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath);
    tmp.writeAsStringSync(serialized);
    if (file.existsSync()) {
      file.copySync('$path.bak');
    }
    tmp.renameSync(path);
  }

  void _writeManagedScript(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == content) {
      if (_platform == ManagedAgentHookPlatform.posix) {
        Process.runSync('chmod', <String>['755', path]);
      }
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(content);
    if (_platform == ManagedAgentHookPlatform.posix) {
      Process.runSync('chmod', <String>['755', tmpPath]);
    }
    tmp.renameSync(path);
  }

  String _agyManagedScript(_AgentHookDescriptor descriptor) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return <String>[
        '@echo off',
        'setlocal',
        'if /I "%${descriptor.eventEnvVar}%"=="Stop" (',
        '  echo {"decision":""}',
        ') else (',
        '  echo {}',
        ')',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(descriptor.agentType.key, descriptor.eventEnvVar),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
      'case "\$${descriptor.eventEnvVar}" in',
      '  Stop)',
      '    printf \'{"decision":""}\\n\'',
      '    ;;',
      '  *)',
      '    printf "{}\\n"',
      '    ;;',
      'esac',
      'if [ -n "\$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -r "\$ALERA_AGENT_HOOK_ENDPOINT" ]; then',
      '  . "\$ALERA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :',
      'fi',
      'if [ -z "\$ALERA_AGENT_HOOK_PORT" ] || [ -z "\$ALERA_AGENT_HOOK_TOKEN" ] || [ -z "\$ALERA_TERMINAL_SESSION_ID" ] || [ -z "\$ALERA_WORKSPACE_ID" ] || [ -z "\$ALERA_TAB_ID" ]; then',
      '  exit 0',
      'fi',
      'payload=\$(cat)',
      'if [ -z "\$payload" ]; then',
      '  exit 0',
      'fi',
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/${descriptor.agentType.key}" \\',
      '  -H "Content-Type: application/x-www-form-urlencoded" \\',
      '  -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '  --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '  --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '  --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '  --data-urlencode "hook_event_name=\${${descriptor.eventEnvVar}}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _windowsPowerShellManagedScript({
    required String source,
    required String eventEnvVar,
    required bool writeEmptyResponse,
  }) {
    return <String>[
      if (writeEmptyResponse) "Write-Output '{}'",
      'if (\$env:ALERA_AGENT_HOOK_ENDPOINT -and (Test-Path -LiteralPath \$env:ALERA_AGENT_HOOK_ENDPOINT)) {',
      '  try {',
      '    Get-Content -LiteralPath \$env:ALERA_AGENT_HOOK_ENDPOINT | ForEach-Object {',
      "      if (\$_ -match '^set ([A-Za-z0-9_]+)=(.*)\$') {",
      "        [Environment]::SetEnvironmentVariable(\$matches[1], \$matches[2], 'Process')",
      '      }',
      '    }',
      '  } catch {}',
      '}',
      'if (-not \$env:ALERA_AGENT_HOOK_PORT -or -not \$env:ALERA_AGENT_HOOK_TOKEN -or -not \$env:ALERA_TERMINAL_SESSION_ID -or -not \$env:ALERA_WORKSPACE_ID -or -not \$env:ALERA_TAB_ID) { exit 0 }',
      '\$inputData = [Console]::In.ReadToEnd()',
      'if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }',
      'try {',
      '  \$payload = \$inputData | ConvertFrom-Json',
      '  \$body = @{',
      '    terminalSessionId = \$env:ALERA_TERMINAL_SESSION_ID',
      '    workspaceId = \$env:ALERA_WORKSPACE_ID',
      '    tabId = \$env:ALERA_TAB_ID',
      '    hookEventName = \$env:$eventEnvVar',
      '    version = \$env:ALERA_AGENT_HOOK_VERSION',
      '    payload = \$payload',
      '  } | ConvertTo-Json -Depth 100',
      "  Invoke-WebRequest -UseBasicParsing -Method Post -Uri ('http://127.0.0.1:' + \$env:ALERA_AGENT_HOOK_PORT + '/hook/$source') -Headers @{ 'Content-Type'='application/json'; '$aleraAgentHookTokenHeader'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$body -TimeoutSec 2 | Out-Null",
      '} catch {}',
      'exit 0',
      '',
    ].join('\r\n');
  }

  String _agyWindowsWrapperPath(String eventName) {
    final fileName = switch (eventName) {
      'PreInvocation' => 'alera-agy-pre-invocation.cmd',
      'PostInvocation' => 'alera-agy-post-invocation.cmd',
      'Stop' => 'alera-agy-stop.cmd',
      'PostToolUse' => 'alera-agy-post-tool-use.cmd',
      _ => 'alera-agy-${eventName.toLowerCase()}.cmd',
    };
    return p.join(_homeDirectory, '.alera', 'agent-hooks', fileName);
  }

  String _agyWindowsWrapperScript(String eventName) {
    return <String>[
      '@echo off',
      'setlocal',
      'set "ALERA_AGY_EVENT=$eventName"',
      'set "ALERA_AGY_CORE=%~dp0alera-agy-hook.cmd"',
      'if exist "%ALERA_AGY_CORE%" (',
      '  call "%ALERA_AGY_CORE%"',
      '  exit /b 0',
      ')',
      'if /I "%ALERA_AGY_EVENT%"=="Stop" (',
      '  echo {"decision":""}',
      ') else (',
      '  echo {}',
      ')',
      'exit /b 0',
      '',
    ].join('\r\n');
  }

  Map<String, Object?> _mapFromValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return <String, Object?>{};
  }

  Map<String, Object?> _hooksMap(Map<String, Object?> config) {
    return _mapFromValue(config['hooks']);
  }

  List<Map<String, Object?>> _definitionsFromValue(Object? value) {
    if (value is! List) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      for (final item in value)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  bool _definitionHasCommand(Map<String, Object?> definition, String command) {
    if (definition['command'] == command ||
        definition['bash'] == command ||
        definition['powershell'] == command) {
      return true;
    }
    final hooks = definition['hooks'];
    if (hooks is! List) {
      return false;
    }
    return hooks.any((hook) => hook is Map && hook['command'] == command);
  }

  List<Map<String, Object?>> _removeManagedCommands(
    List<Map<String, Object?>> definitions,
    List<String> scriptFileNames,
  ) {
    return definitions
        .expand((definition) {
          final next = <String, Object?>{...definition};
          for (final key in const <String>['command', 'bash', 'powershell']) {
            if (_isManagedCommand(next[key], scriptFileNames)) {
              next.remove(key);
            }
          }
          final hooks = next['hooks'];
          if (hooks is List) {
            final cleanedHooks = <Object?>[
              for (final hook in hooks)
                if (hook is! Map ||
                    !_isManagedCommand(hook['command'], scriptFileNames))
                  hook,
            ];
            if (cleanedHooks.isEmpty) {
              next.remove('hooks');
            } else {
              next['hooks'] = cleanedHooks;
            }
          }
          final hasCommand =
              next['command'] is String ||
              next['bash'] is String ||
              next['powershell'] is String ||
              (next['hooks'] is List && (next['hooks'] as List).isNotEmpty);
          return hasCommand
              ? <Map<String, Object?>>[next]
              : const <Map<String, Object?>>[];
        })
        .toList(growable: false);
  }

  bool _isManagedCommand(Object? command, List<String> scriptFileNames) {
    if (command is! String) {
      return false;
    }
    final normalized = command.replaceAll(r'\', '/');
    return scriptFileNames.any(
      (scriptFileName) => normalized.contains('agent-hooks/$scriptFileName'),
    );
  }

  static String _resolveHome(Map<String, String>? environment) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.trim().isEmpty) {
      throw StateError('Could not resolve the user home directory.');
    }
    return home;
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
