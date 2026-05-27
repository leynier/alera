import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    final config = _readJsonObject(descriptor.settingsPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.settingsPath,
        managedHooksPresent: false,
        detail: 'Could not parse Claude runtime settings.json.',
      );
    }

    final missing = <String>[];
    var presentCount = 0;
    final hooks = _hooksMap(config);
    for (final event in _claudeEvents) {
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

    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: descriptor.settingsPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.installed,
        configPath: descriptor.settingsPath,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.claude,
      state: ManagedAgentHookInstallState.partial,
      configPath: descriptor.settingsPath,
      managedHooksPresent: true,
      detail: 'Managed hook missing for events: ${missing.join(', ')}.',
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

    final nextConfig = <String, Object?>{...sourceConfig};
    final hooks = _hooksMap(nextConfig);
    for (final entry in hooks.entries.toList(growable: false)) {
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
    for (final event in _claudeEvents) {
      final current = _definitionsFromValue(hooks[event.eventName]);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.managedScriptFileNames,
      );
      hooks[event.eventName] = <Object?>[
        ...cleaned,
        _managedHookDefinition(
          event,
          _managedCommand(descriptor: descriptor, event: event),
        ),
      ];
    }
    nextConfig['hooks'] = hooks;
    _writeManagedScript(descriptor.scriptPath, _managedScript());
    _writeJsonObject(descriptor.settingsPath, nextConfig);
    return status();
  }

  Future<ManagedAgentHookInstallStatus> remove() async {
    final runtimeHome = await _runtimeHomeDirectory();
    final descriptor = _descriptor(runtimeHome);
    final config = _readJsonObject(descriptor.settingsPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.settingsPath,
        managedHooksPresent: false,
        detail: 'Could not parse Claude runtime settings.json.',
      );
    }
    final hooks = _hooksMap(config);
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
      config['hooks'] = hooks;
      _writeJsonObject(descriptor.settingsPath, config);
    }
    return status();
  }

  Future<Directory> _runtimeHomeDirectory() async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'agent-runtime-homes', 'claude', 'home'),
    );
    directory.createSync(recursive: true);
    return directory;
  }

  Directory _sourceConfigDirectory(Directory runtimeHome) {
    final inherited = _environment['CLAUDE_CONFIG_DIR']?.trim();
    if (inherited != null &&
        inherited.isNotEmpty &&
        !_samePath(inherited, runtimeHome.path)) {
      return Directory(inherited);
    }
    return Directory(p.join(_homeDirectory, '.claude'));
  }

  _ClaudeRuntimeHookDescriptor _descriptor(Directory runtimeHome) {
    final extension = switch (_platform) {
      ManagedAgentHookPlatform.posix => 'sh',
      ManagedAgentHookPlatform.windows => 'cmd',
    };
    final scriptFileName = 'alera-claude-hook.$extension';
    return _ClaudeRuntimeHookDescriptor(
      settingsPath: p.join(runtimeHome.path, 'settings.json'),
      scriptPath: p.join(
        _homeDirectory,
        '.alera',
        'agent-hooks',
        scriptFileName,
      ),
      managedScriptFileNames: <String>{scriptFileName},
    );
  }

  void _syncRuntimeResources(Directory runtimeHome, Directory source) {
    final expected = <String, String>{};
    if (source.existsSync()) {
      for (final entity in source.listSync(followLinks: false)) {
        final entryName = p.basename(entity.path);
        if (entryName == 'settings.json') {
          continue;
        }
        expected[entryName] = entity.path;
      }
    }

    final legacyConfig = File(p.join(_homeDirectory, '.claude.json'));
    if (_samePath(source.path, p.join(_homeDirectory, '.claude')) &&
        legacyConfig.existsSync()) {
      expected['.claude.json'] = legacyConfig.path;
    }

    for (final entry in expected.entries) {
      _syncLinkedResource(
        runtimeHomePath: runtimeHome.path,
        entryName: entry.key,
        sourcePath: entry.value,
      );
    }
    _removeStaleRuntimeResources(runtimeHome, expected);
  }

  void _syncKeychainCredentials(Directory runtimeHome) {
    final keychain = _keychainCredentialsStore;
    if (keychain == null) {
      return;
    }
    try {
      final legacyCredentials = keychain.readLegacyCredentials();
      if (legacyCredentials == null || legacyCredentials.isEmpty) {
        keychain.deleteScopedCredentials(runtimeHome.path);
        return;
      }
      keychain.writeScopedCredentials(
        configDir: runtimeHome.path,
        credentials: legacyCredentials,
      );
    } catch (_) {}
  }

  void _syncLinkedResource({
    required String runtimeHomePath,
    required String entryName,
    required String sourcePath,
  }) {
    final targetPath = p.join(runtimeHomePath, entryName);
    if (!_sourceExists(sourcePath)) {
      _removeOwnedRuntimeResource(targetPath, runtimeHomePath, entryName);
      return;
    }
    if (_targetAlreadyPointsToSource(targetPath, sourcePath)) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }

    final targetType = FileSystemEntity.typeSync(
      targetPath,
      followLinks: false,
    );
    String? sourceFingerprint;
    if (targetType != FileSystemEntityType.notFound) {
      final marker = _copiedResourceMarker(runtimeHomePath, entryName);
      final isOwnedFallbackCopy = marker?.sourcePath == sourcePath;
      if (targetType != FileSystemEntityType.link && !isOwnedFallbackCopy) {
        return;
      }
      sourceFingerprint = _resourceFingerprint(sourcePath);
      if (isOwnedFallbackCopy &&
          marker?.sourceFingerprint == sourceFingerprint) {
        return;
      }
      _deleteEntity(targetPath);
    }

    try {
      _resourceLinkCreator(sourcePath: sourcePath, targetPath: targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    } catch (_) {}

    try {
      _deleteEntity(targetPath);
      _copyEntity(sourcePath, targetPath);
      _markCopiedResource(
        runtimeHomePath,
        entryName,
        sourcePath,
        sourceFingerprint ?? _resourceFingerprint(sourcePath),
      );
    } catch (_) {}
  }

  void _removeStaleRuntimeResources(
    Directory runtimeHome,
    Map<String, String> expected,
  ) {
    for (final entity in runtimeHome.listSync(followLinks: false)) {
      final entryName = p.basename(entity.path);
      if (entryName == 'settings.json' ||
          entryName.startsWith('.alera-copied-')) {
        continue;
      }
      final sourcePath = expected[entryName];
      if (sourcePath == null) {
        _removeOwnedRuntimeResource(entity.path, runtimeHome.path, entryName);
        continue;
      }
      if (_targetAlreadyPointsToSource(entity.path, sourcePath) ||
          _targetIsOwnedFallbackCopy(runtimeHome.path, entryName, sourcePath)) {
        continue;
      }
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        _deleteEntity(entity.path);
        _clearCopiedResourceMarker(runtimeHome.path, entryName);
      }
    }
  }

  void _removeOwnedRuntimeResource(
    String targetPath,
    String runtimeHomePath,
    String entryName,
  ) {
    final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }
    if (type == FileSystemEntityType.link ||
        _copiedResourceMarker(runtimeHomePath, entryName) != null) {
      _deleteEntity(targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
    }
  }

  bool _targetAlreadyPointsToSource(String targetPath, String sourcePath) {
    try {
      final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
      if (type != FileSystemEntityType.link) {
        return false;
      }
      final target = Link(targetPath).targetSync();
      final absoluteTarget = p.isAbsolute(target)
          ? target
          : p.normalize(p.join(p.dirname(targetPath), target));
      return _samePath(absoluteTarget, sourcePath);
    } catch (_) {
      return false;
    }
  }

  bool _targetIsOwnedFallbackCopy(
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    final marker = _copiedResourceMarker(runtimeHomePath, entryName);
    return marker?.sourcePath == sourcePath;
  }

  bool _sourceExists(String sourcePath) {
    return FileSystemEntity.isDirectorySync(sourcePath) ||
        FileSystemEntity.isFileSync(sourcePath) ||
        Link(sourcePath).existsSync();
  }

  _CopiedResourceMarker? _copiedResourceMarker(
    String runtimeHomePath,
    String entryName,
  ) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    if (!marker.existsSync()) {
      return null;
    }
    try {
      final parsed = jsonDecode(marker.readAsStringSync());
      if (parsed is Map && parsed['sourcePath'] is String) {
        return _CopiedResourceMarker(
          sourcePath: parsed['sourcePath'] as String,
          sourceFingerprint: parsed['sourceFingerprint'] is String
              ? parsed['sourceFingerprint'] as String
              : null,
        );
      }
    } catch (_) {}
    return null;
  }

  void _markCopiedResource(
    String runtimeHomePath,
    String entryName,
    String sourcePath,
    String sourceFingerprint,
  ) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync(
      '${jsonEncode(<String, String>{'sourcePath': sourcePath, 'sourceFingerprint': sourceFingerprint})}\n',
    );
  }

  void _clearCopiedResourceMarker(String runtimeHomePath, String entryName) {
    final marker = File(_copiedResourceMarkerPath(runtimeHomePath, entryName));
    if (marker.existsSync()) {
      marker.deleteSync();
    }
  }

  String _copiedResourceMarkerPath(String runtimeHomePath, String entryName) {
    return p.join(runtimeHomePath, '.alera-copied-$entryName.json');
  }

  String _resourceFingerprint(String sourcePath) {
    final records = <Map<String, Object?>>[];
    void collect(String currentPath, String relativePath) {
      final type = FileSystemEntity.typeSync(currentPath, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        final stat = Directory(currentPath).statSync();
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'directory',
          'modified': stat.modified.microsecondsSinceEpoch,
        });
        final children = Directory(currentPath).listSync(followLinks: false)
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
        for (final child in children) {
          final childRelativePath = relativePath.isEmpty
              ? p.basename(child.path)
              : p.join(relativePath, p.basename(child.path));
          collect(child.path, childRelativePath);
        }
        return;
      }
      if (type == FileSystemEntityType.file) {
        final stat = File(currentPath).statSync();
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'file',
          'size': stat.size,
          'modified': stat.modified.microsecondsSinceEpoch,
        });
        return;
      }
      if (type == FileSystemEntityType.link) {
        String? target;
        try {
          target = Link(currentPath).targetSync();
        } catch (_) {}
        records.add(<String, Object?>{
          'path': relativePath,
          'type': 'link',
          'target': target,
        });
      }
    }

    collect(sourcePath, '');
    return 'sha256:${sha256.convert(utf8.encode(jsonEncode(records)))}';
  }

  void _copyEntity(String sourcePath, String targetPath) {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      final target = Directory(targetPath)..createSync(recursive: true);
      for (final child in Directory(sourcePath).listSync(followLinks: false)) {
        _copyEntity(child.path, p.join(target.path, p.basename(child.path)));
      }
      return;
    }
    if (type == FileSystemEntityType.file) {
      File(sourcePath).copySync(targetPath);
    }
  }

  void _deleteEntity(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
      return;
    }
    FileSystemEntity.isLinkSync(path)
        ? Link(path).deleteSync()
        : File(path).deleteSync();
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
    final tmp = File(tmpPath)..writeAsStringSync(serialized);
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

  String _managedCommand({
    required _ClaudeRuntimeHookDescriptor descriptor,
    required _ClaudeHookEvent event,
  }) {
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(descriptor.scriptPath)} ]; then '
            'ALERA_AGENT_HOOK_EVENT=${_shQuote(event.eventName)} '
            '/bin/sh ${_shQuote(descriptor.scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        'cmd /d /s /c "if exist ""${descriptor.scriptPath}"" '
            '(set ALERA_AGENT_HOOK_EVENT=${event.eventName}&& call ""${descriptor.scriptPath}"")"',
    };
  }

  Map<String, Object?> _managedHookDefinition(
    _ClaudeHookEvent event,
    String command,
  ) {
    return <String, Object?>{
      if (event.matcher != null) 'matcher': event.matcher,
      'hooks': <Object?>[
        <String, Object?>{'type': 'command', 'command': command},
      ],
    };
  }

  String _managedScript() {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return <String>[
        '@echo off',
        'setlocal',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
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
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/claude" \\',
      '  -H "Content-Type: application/x-www-form-urlencoded" \\',
      '  -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '  --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '  --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '  --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '  --data-urlencode "hookEventName=\${ALERA_AGENT_HOOK_EVENT}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _windowsPostCommand() {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:ALERA_AGENT_HOOK_EVENT; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/claude\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
  }

  Map<String, Object?> _hooksMap(Map<String, Object?> config) {
    final hooks = config['hooks'];
    if (hooks is Map) {
      return Map<String, Object?>.from(hooks);
    }
    return <String, Object?>{};
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
    Set<String> scriptFileNames,
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

  bool _isManagedCommand(Object? command, Set<String> scriptFileNames) {
    if (command is! String) {
      return false;
    }
    final normalized = command.replaceAll(r'\', '/');
    return scriptFileNames.any(
      (scriptFileName) => normalized.contains('agent-hooks/$scriptFileName'),
    );
  }

  bool _samePath(String left, String right) {
    return _absoluteNormalizedPath(left) == _absoluteNormalizedPath(right);
  }

  String _absoluteNormalizedPath(String path) {
    final absolute = p.isAbsolute(path) ? path : p.absolute(path);
    return p.normalize(absolute);
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

void _createResourceLink({
  required String sourcePath,
  required String targetPath,
}) {
  Link(targetPath).createSync(sourcePath);
}

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
