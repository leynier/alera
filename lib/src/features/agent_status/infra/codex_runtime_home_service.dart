import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef CodexApplicationSupportDirectoryResolver = Future<Directory> Function();
typedef CodexResourceLinkCreator =
    void Function({required String sourcePath, required String targetPath});

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

  String get _systemHomePath => p.join(_homeDirectory, '.codex');

  void _syncAuth(Directory runtimeHome) {
    final source = File(p.join(_systemHomePath, 'auth.json'));
    final target = File(p.join(runtimeHome.path, 'auth.json'));
    if (!source.existsSync()) {
      _deleteEntity(target.path);
      return;
    }
    if (target.existsSync()) {
      final sourceStat = source.statSync();
      final targetStat = target.statSync();
      if (!sourceStat.modified.isAfter(targetStat.modified) &&
          target.readAsStringSync() != '') {
        return;
      }
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    if (_platform == ManagedAgentHookPlatform.posix) {
      Process.runSync('chmod', <String>['600', target.path]);
    }
  }

  void _syncSystemResources(Directory runtimeHome) {
    for (final entryName in _codexSystemResourceEntries) {
      _syncLinkedResource(
        systemHomePath: _systemHomePath,
        runtimeHomePath: runtimeHome.path,
        entryName: entryName,
        allowCopyFallback: true,
      );
    }
  }

  void _syncSystemSessions(Directory runtimeHome) {
    _syncLinkedResource(
      systemHomePath: _systemHomePath,
      runtimeHomePath: runtimeHome.path,
      entryName: 'sessions',
      allowCopyFallback: false,
    );
  }

  void _syncLinkedResource({
    required String systemHomePath,
    required String runtimeHomePath,
    required String entryName,
    required bool allowCopyFallback,
  }) {
    final sourcePath = p.join(systemHomePath, entryName);
    final targetPath = p.join(runtimeHomePath, entryName);
    if (!FileSystemEntity.isDirectorySync(sourcePath) &&
        !FileSystemEntity.isFileSync(sourcePath) &&
        !Link(sourcePath).existsSync()) {
      _removeOwnedRuntimeResource(
        targetPath,
        runtimeHomePath,
        entryName,
        sourcePath,
      );
      return;
    }
    if (_targetAlreadyPointsToSource(targetPath, sourcePath)) {
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    }
    final targetExists =
        FileSystemEntity.typeSync(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound;
    String? sourceFingerprint;
    if (targetExists) {
      final marker = _copiedResourceMarker(runtimeHomePath, entryName);
      final isOwnedFallbackCopy = marker?.sourcePath == sourcePath;
      if (!isOwnedFallbackCopy) {
        return;
      }
      sourceFingerprint = _resourceFingerprint(sourcePath);
      if (marker?.sourceFingerprint == sourceFingerprint) {
        return;
      }
      _deleteEntity(targetPath);
    }
    try {
      _resourceLinkCreator(sourcePath: sourcePath, targetPath: targetPath);
      _clearCopiedResourceMarker(runtimeHomePath, entryName);
      return;
    } catch (_) {
      if (!allowCopyFallback) {
        return;
      }
    }
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

  void _removeOwnedRuntimeResource(
    String targetPath,
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    if (_targetAlreadyPointsToSource(targetPath, sourcePath) ||
        _targetIsOwnedFallbackCopy(
          targetPath,
          runtimeHomePath,
          entryName,
          sourcePath,
        )) {
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
      return p.normalize(absoluteTarget) == p.normalize(sourcePath);
    } catch (_) {
      return false;
    }
  }

  bool _targetIsOwnedFallbackCopy(
    String targetPath,
    String runtimeHomePath,
    String entryName,
    String sourcePath,
  ) {
    if (FileSystemEntity.typeSync(targetPath, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return false;
    }
    final marker = _copiedResourceMarker(runtimeHomePath, entryName);
    return marker?.sourcePath == sourcePath;
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
        return;
      }
      records.add(<String, Object?>{
        'path': relativePath,
        'type': _fileSystemEntityTypeName(type),
      });
    }

    collect(sourcePath, '');
    final serialized = jsonEncode(_canonicalize(records));
    return 'sha256:${sha256.convert(utf8.encode(serialized))}';
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

  void _syncSystemConfig(Directory runtimeHome) {
    final systemPath = p.join(_systemHomePath, 'config.toml');
    final runtimePath = p.join(runtimeHome.path, 'config.toml');
    final systemExists = File(systemPath).existsSync();
    final runtimeExists = File(runtimePath).existsSync();
    final systemConfig = _normalizeDeprecatedHookFeatureFlag(
      systemExists ? _readTextFile(systemPath) : '',
    );
    if (!runtimeExists) {
      _writeTextAtomically(
        runtimePath,
        _ensureHooksFeatureEnabled(
          _stripRuntimeOwnedTomlSections(systemConfig),
        ),
      );
      return;
    }
    final runtimeConfig = _readTextFile(runtimePath);
    final merged = _ensureHooksFeatureEnabled(
      _mergeSystemConfigIntoRuntime(runtimeConfig, systemConfig),
    );
    if (merged != runtimeConfig) {
      _writeTextAtomically(runtimePath, merged);
    }
  }

  String _normalizeDeprecatedHookFeatureFlag(String config) {
    if (!config.contains('codex_hooks')) {
      return config;
    }
    final lines = config.split('\n');
    final featureSections = _tomlSections(
      config,
    ).where((section) => _sectionHeaderKey(section.header) == '[features]');
    for (final section in featureSections.toList(growable: false).reversed) {
      final start = section.start + 1;
      final end = section.start + section.block.split('\n').length;
      final deprecated = <int>[];
      var hasHooks = false;
      for (var index = start; index < end; index++) {
        final line = lines[index];
        if (RegExp(r'^[ \t]*hooks[ \t]*=').hasMatch(line)) {
          hasHooks = true;
        }
        if (RegExp(r'^[ \t]*codex_hooks[ \t]*=').hasMatch(line)) {
          deprecated.add(index);
        }
      }
      if (deprecated.isEmpty) {
        continue;
      }
      if (!hasHooks) {
        final first = deprecated.removeAt(0);
        lines[first] = lines[first].replaceFirstMapped(
          RegExp(r'^([ \t]*)codex_hooks([ \t]*=)'),
          (match) => '${match.group(1)}hooks${match.group(2)}',
        );
      }
      for (final index in deprecated.reversed) {
        lines.removeAt(index);
      }
    }
    return lines.join('\n');
  }

  String _mergeSystemConfigIntoRuntime(
    String runtimeConfig,
    String systemConfig,
  ) {
    final runtimeSections = _tomlSections(runtimeConfig);
    final systemProjectKeys = _tomlSections(systemConfig)
        .where((section) => _isProjectSection(section.header))
        .map((section) => _sectionHeaderKey(section.header))
        .toSet();
    return _joinTomlBlocks(<String>[
      _stripRuntimeOwnedTomlSections(systemConfig),
      for (final section in runtimeSections)
        if (_isHookStateSection(section.header) ||
            (_isProjectSection(section.header) &&
                !systemProjectKeys.contains(_sectionHeaderKey(section.header))))
          section.block,
    ]);
  }

  String _ensureHooksFeatureEnabled(String config) {
    final sections = _tomlSections(config);
    _TomlSection? featureSection;
    for (final section in sections) {
      if (_sectionHeaderKey(section.header) == '[features]') {
        featureSection = section;
        break;
      }
    }
    if (featureSection == null) {
      return _joinTomlBlocks(<String>[config, '[features]\nhooks = true']);
    }

    final lines = config.split('\n');
    final start = featureSection.start + 1;
    final end = featureSection.start + featureSection.block.split('\n').length;
    var multilineState = const _TomlMultilineState();
    var hooksLineIndex = -1;
    for (var index = start; index < end; index++) {
      final line = lines[index];
      if (!_isInsideTomlMultilineString(multilineState) &&
          RegExp(r'^[ \t]*hooks[ \t]*=').hasMatch(line)) {
        hooksLineIndex = index;
        break;
      }
      multilineState = _updateTomlMultilineState(multilineState, line);
    }
    if (hooksLineIndex >= 0) {
      lines[hooksLineIndex] = lines[hooksLineIndex].replaceFirstMapped(
        RegExp(r'^([ \t]*)hooks[ \t]*=.*$'),
        (match) => '${match.group(1)}hooks = true',
      );
      return _joinTomlBlocks(<String>[lines.join('\n')]);
    }

    var insertIndex = end;
    while (insertIndex > start && lines[insertIndex - 1].trim().isEmpty) {
      insertIndex -= 1;
    }
    lines.insert(insertIndex, 'hooks = true');
    return _joinTomlBlocks(<String>[lines.join('\n')]);
  }

  String _stripRuntimeOwnedTomlSections(String config) {
    final sections = _tomlSections(config);
    final firstStart = sections.isEmpty ? -1 : sections.first.start;
    final preamble = firstStart < 0
        ? config
        : config.split('\n').take(firstStart).join('\n');
    return _joinTomlBlocks(<String>[
      preamble,
      for (final section in sections)
        if (!_isHookStateSection(section.header)) section.block,
    ]);
  }

  _RuntimeHookPlan _runtimeHooksWithSystemUserHooks(
    _CodexRuntimeHookDescriptor descriptor,
  ) {
    final systemConfig = _readJsonObject(descriptor.systemConfigPath);
    if (systemConfig == null || systemConfig['hooks'] is! Map) {
      return _RuntimeHookPlan(
        <String, Object?>{},
        <_MirroredRuntimeUserHookTrustEntry>[],
      );
    }
    final trustedSystemHookSignatures = _trustedSystemUserHookSignatures(
      descriptor,
      Map<String, Object?>.from(systemConfig['hooks'] as Map),
    );
    final nextHooks = <String, Object?>{};
    for (final entry in Map<String, Object?>.from(
      systemConfig['hooks'] as Map,
    ).entries) {
      final definitions = _definitionsFromValue(entry.value);
      final userDefinitions = _removeManagedCommands(
        definitions,
        descriptor.managedScriptFileNames,
      );
      if (userDefinitions.isNotEmpty) {
        nextHooks[entry.key] = _dedupeHookDefinitions(userDefinitions);
      }
    }
    return _RuntimeHookPlan(
      nextHooks,
      _collectMirroredRuntimeUserHookTrustEntries(
        runtimeConfigPath: descriptor.configPath,
        runtimeHooks: nextHooks,
        trustedSystemHookSignatures: trustedSystemHookSignatures,
        managedScriptFileNames: descriptor.managedScriptFileNames,
      ),
    );
  }

  Map<String, bool> _trustedSystemUserHookSignatures(
    _CodexRuntimeHookDescriptor descriptor,
    Map<String, Object?> systemHooks,
  ) {
    final signatures = <String, bool>{};
    final trustEntries = _readHookTrustEntries(descriptor.systemTomlPath);
    for (final eventEntry in systemHooks.entries) {
      final definitions = _definitionsFromValue(eventEntry.value);
      for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
        final definition = definitions[groupIndex];
        final handlers = _hookHandlers(definition);
        for (
          var handlerIndex = 0;
          handlerIndex < handlers.length;
          handlerIndex++
        ) {
          final hook = handlers[handlerIndex];
          if (_isManagedCommand(
            hook['command'] as String?,
            descriptor.managedScriptFileNames,
          )) {
            continue;
          }
          final entry = _createTrustEntry(
            sourcePath: descriptor.systemConfigPath,
            eventName: eventEntry.key,
            groupIndex: groupIndex,
            handlerIndex: handlerIndex,
            definition: definition,
            hook: hook,
          );
          if (entry == null) {
            continue;
          }
          final state = trustEntries[_computeTrustKey(entry)];
          if (state?.trustedHash == _computeTrustedHash(entry)) {
            final signature = _trustSignature(entry);
            final enabled = state?.enabled != false;
            if (enabled || !signatures.containsKey(signature)) {
              signatures[signature] = enabled;
            }
          }
        }
      }
    }
    return signatures;
  }

  List<_MirroredRuntimeUserHookTrustEntry>
  _collectMirroredRuntimeUserHookTrustEntries({
    required String runtimeConfigPath,
    required Map<String, Object?> runtimeHooks,
    required Map<String, bool> trustedSystemHookSignatures,
    required Set<String> managedScriptFileNames,
  }) {
    if (trustedSystemHookSignatures.isEmpty) {
      return const <_MirroredRuntimeUserHookTrustEntry>[];
    }
    final entries = <_MirroredRuntimeUserHookTrustEntry>[];
    for (final eventEntry in runtimeHooks.entries) {
      final definitions = _definitionsFromValue(eventEntry.value);
      for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
        final definition = definitions[groupIndex];
        final handlers = _hookHandlers(definition);
        for (
          var handlerIndex = 0;
          handlerIndex < handlers.length;
          handlerIndex++
        ) {
          final hook = handlers[handlerIndex];
          if (_isManagedCommand(
            hook['command'] as String?,
            managedScriptFileNames,
          )) {
            continue;
          }
          final entry = _createTrustEntry(
            sourcePath: runtimeConfigPath,
            eventName: eventEntry.key,
            groupIndex: groupIndex,
            handlerIndex: handlerIndex,
            definition: definition,
            hook: hook,
          );
          if (entry == null) {
            continue;
          }
          final enabled = trustedSystemHookSignatures[_trustSignature(entry)];
          if (enabled != null) {
            entries.add(_MirroredRuntimeUserHookTrustEntry(entry, enabled));
          }
        }
      }
    }
    return entries;
  }

  List<_CodexHookTrustEntry> _collectManagedTrustEntries({
    required String sourcePath,
    required String eventName,
    required List<Map<String, Object?>> definitions,
    required Set<String> managedScriptFileNames,
  }) {
    final entries = <_CodexHookTrustEntry>[];
    for (var groupIndex = 0; groupIndex < definitions.length; groupIndex++) {
      final definition = definitions[groupIndex];
      final handlers = _hookHandlers(definition);
      for (
        var handlerIndex = 0;
        handlerIndex < handlers.length;
        handlerIndex++
      ) {
        final hook = handlers[handlerIndex];
        if (!_isManagedCommand(
          hook['command'] as String?,
          managedScriptFileNames,
        )) {
          continue;
        }
        final entry = _createTrustEntry(
          sourcePath: sourcePath,
          eventName: eventName,
          groupIndex: groupIndex,
          handlerIndex: handlerIndex,
          definition: definition,
          hook: hook,
        );
        if (entry != null) {
          entries.add(entry);
        }
      }
    }
    return entries;
  }

  _CodexHookTrustEntry? _createTrustEntry({
    required String sourcePath,
    required String eventName,
    required int groupIndex,
    required int handlerIndex,
    required Map<String, Object?> definition,
    required Map<String, Object?> hook,
  }) {
    final command = hook['command'];
    if (command is! String ||
        command.isEmpty ||
        !_codexEventLabels.containsKey(eventName)) {
      return null;
    }
    return _CodexHookTrustEntry(
      sourcePath: sourcePath,
      eventLabel: _codexEventLabel(eventName),
      groupIndex: groupIndex,
      handlerIndex: handlerIndex,
      command: command,
      timeoutSec: hook['timeout'] is num
          ? (hook['timeout'] as num).toInt()
          : null,
      async: hook['async'] is bool ? hook['async'] as bool : null,
      matcher: definition['matcher'] is String
          ? definition['matcher'] as String
          : null,
      statusMessage: hook['statusMessage'] is String
          ? hook['statusMessage'] as String
          : null,
    );
  }

  void _upsertHookTrustEntries(
    String configPath,
    Iterable<_MirroredRuntimeUserHookTrustEntry> entries,
  ) {
    final list = entries.toList(growable: false);
    if (list.isEmpty) {
      return;
    }
    final existing = File(configPath).existsSync()
        ? _readTextFile(configPath)
        : '';
    var updated = existing;
    for (final mirrored in list) {
      updated = _upsertTrustBlock(
        updated,
        _computeTrustKey(mirrored.entry),
        _computeTrustedHash(mirrored.entry),
        mirrored.enabled,
      );
    }
    if (updated != existing) {
      _writeTextAtomically(configPath, updated);
    }
  }

  void _removeStaleRuntimeTrustEntries({
    required String tomlPath,
    required String runtimeHooksPath,
    required List<_CodexHookTrustEntry> expectedEntries,
  }) {
    final expected = <String, String>{
      for (final entry in expectedEntries)
        _computeTrustKey(entry): _computeTrustedHash(entry),
    };
    final canonicalRuntimeHooksPath = _canonicalTrustPath(runtimeHooksPath);
    final stale = <String>[];
    for (final entry in _readHookTrustEntries(tomlPath).entries) {
      final parsed = _parseTrustKey(entry.key);
      if (parsed == null ||
          _canonicalTrustPath(parsed.sourcePath) != canonicalRuntimeHooksPath) {
        continue;
      }
      if (expected[entry.key] != entry.value.trustedHash) {
        stale.add(entry.key);
      }
    }
    _removeHookTrustEntries(tomlPath, stale);
  }

  void _removeMatchingTrustEntries(
    String configPath,
    List<_CodexHookTrustEntry> entries,
  ) {
    if (entries.isEmpty) {
      return;
    }
    final existing = _readHookTrustEntries(configPath);
    final keys = <String>[];
    for (final entry in entries) {
      final key = _computeTrustKey(entry);
      if (existing[key]?.trustedHash == _computeTrustedHash(entry)) {
        keys.add(key);
      }
    }
    _removeHookTrustEntries(configPath, keys);
  }

  void _removeHookTrustEntries(String configPath, List<String> keys) {
    if (keys.isEmpty || !File(configPath).existsSync()) {
      return;
    }
    final existing = _readTextFile(configPath);
    var updated = existing;
    for (final key in keys) {
      updated = _removeTrustBlock(updated, key);
    }
    if (updated != existing) {
      _writeTextAtomically(configPath, updated);
    }
  }

  Map<String, _CodexHookTrustState> _readHookTrustEntries(String configPath) {
    final result = <String, _CodexHookTrustState>{};
    final file = File(configPath);
    if (!file.existsSync()) {
      return result;
    }
    final content = _readTextFile(configPath);
    final headerRegex = RegExp(
      r'^[ \t]*\[hooks\.state\."((?:[^"\\]|\\.)*)"\][ \t]*(?:#[^\r\n]*)?$',
    );
    var cursor = 0;
    var multilineState = const _TomlMultilineState();
    while (cursor < content.length) {
      final newlineIndex = content.indexOf('\n', cursor);
      final lineEnd = newlineIndex < 0 ? content.length : newlineIndex;
      final line = content
          .substring(cursor, lineEnd)
          .replaceFirst(RegExp(r'\r$'), '');
      final nextCursor = newlineIndex < 0 ? content.length : newlineIndex + 1;
      if (_isInsideTomlMultilineString(multilineState)) {
        multilineState = _updateTomlMultilineState(multilineState, line);
        cursor = nextCursor;
        continue;
      }
      final match = headerRegex.firstMatch(line);
      if (match != null) {
        final after = content.substring(nextCursor);
        final nextHeader = _findNextTableHeader(after);
        final blockEnd = nextHeader < 0
            ? content.length
            : nextCursor + nextHeader;
        final blockText = content.substring(nextCursor, blockEnd);
        final hashMatch = RegExp(
          r'^[ \t]*trusted_hash[ \t]*=[ \t]*"((?:[^"\\]|\\.)*)"',
          multiLine: true,
        ).firstMatch(blockText);
        final enabledMatch = RegExp(
          r'^[ \t]*enabled[ \t]*=[ \t]*(true|false)[ \t\r]*(?:#.*)?$',
          multiLine: true,
        ).firstMatch(blockText);
        result[_unescapeTomlString(match.group(1)!)] = _CodexHookTrustState(
          trustedHash: hashMatch == null
              ? null
              : _unescapeTomlString(hashMatch.group(1)!),
          enabled: enabledMatch == null
              ? null
              : enabledMatch.group(1) == 'true',
        );
      }
      multilineState = _updateTomlMultilineState(multilineState, line);
      cursor = nextCursor;
    }
    return result;
  }

  String _upsertTrustBlock(
    String content,
    String key,
    String hash,
    bool enabled,
  ) {
    final headerPattern = _tomlHeaderPattern('hooks.state', key);
    final match = headerPattern.firstMatch(content);
    final block = <String>[
      '[hooks.state."${_escapeTomlString(key)}"]',
      'enabled = $enabled',
      'trusted_hash = "${_escapeTomlString(hash)}"',
    ].join('\n');
    if (match == null) {
      final separator = content.isEmpty
          ? ''
          : content.endsWith('\n\n')
          ? ''
          : content.endsWith('\n')
          ? '\n'
          : '\n\n';
      return '$content$separator$block\n';
    }
    final cutStart = match.start + ((match.group(1) ?? '').length);
    final afterHeader = content.substring(match.end);
    final nextHeader = _findNextTableHeader(afterHeader);
    final cutEnd = nextHeader < 0 ? content.length : match.end + nextHeader;
    return '${content.substring(0, cutStart)}$block\n${content.substring(cutEnd)}';
  }

  String _removeTrustBlock(String content, String key) {
    final headerPattern = _tomlHeaderPattern('hooks.state', key);
    final match = headerPattern.firstMatch(content);
    if (match == null) {
      return content;
    }
    final cutStart = match.start + ((match.group(1) ?? '').length);
    final afterHeader = content.substring(match.end);
    final nextHeader = _findNextTableHeader(afterHeader);
    final cutEnd = nextHeader < 0 ? content.length : match.end + nextHeader;
    return content.substring(0, cutStart) + content.substring(cutEnd);
  }

  RegExp _tomlHeaderPattern(String prefix, String key) {
    final escapedPrefix = RegExp.escape(prefix);
    final escaped = RegExp.escape(_escapeTomlString(key));
    return RegExp(
      '(^|\\r?\\n)[ \\t]*\\[$escapedPrefix\\."$escaped"\\][ \\t]*(?:#[^\\r\\n]*)?(?=\\r?\\n|\\\$)',
    );
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
    } catch (_) {}
    return null;
  }

  void _writeJsonObject(String path, Map<String, Object?> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final serialized =
        '${const JsonEncoder.withIndent('  ').convert(config)}\n';
    if (file.existsSync() && file.readAsStringSync() == serialized) {
      return;
    }
    if (file.existsSync()) {
      file.copySync('$path.bak');
    }
    final tmp = File(
      p.join(file.parent.path, '.${DateTime.now().microsecondsSinceEpoch}.tmp'),
    )..writeAsStringSync(serialized);
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

  String _managedCommand(String scriptPath, String eventName) {
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(scriptPath)} ]; then '
            'ALERA_AGENT_HOOK_EVENT=${_shQuote(eventName)} '
            '/bin/sh ${_shQuote(scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        'cmd /d /s /c "if exist ""$scriptPath"" '
            '(set ALERA_AGENT_HOOK_EVENT=$eventName&& call ""$scriptPath"")"',
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
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/codex" \\',
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
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:ALERA_AGENT_HOOK_EVENT; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/codex\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
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
  const _ParsedTrustKey({required this.sourcePath});

  final String sourcePath;
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

List<Map<String, Object?>> _definitionsFromValue(Object? value) {
  if (value is! List) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

List<Map<String, Object?>> _hookHandlers(Map<String, Object?> definition) {
  final hooks = definition['hooks'];
  if (hooks is! List) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final hook in hooks)
      if (hook is Map) Map<String, Object?>.from(hook),
  ];
}

Map<String, Object?> _hooksMap(Map<String, Object?> config) {
  final hooks = config['hooks'];
  if (hooks is Map) {
    return Map<String, Object?>.from(hooks);
  }
  return <String, Object?>{};
}

List<Map<String, Object?>> _removeManagedCommands(
  List<Map<String, Object?>> definitions,
  Set<String> managedScriptFileNames,
) {
  final cleaned = <Map<String, Object?>>[];
  for (final definition in definitions) {
    final hooks = definition['hooks'];
    if (hooks is! List) {
      cleaned.add(definition);
      continue;
    }
    final nextHooks = <Object?>[
      for (final hook in hooks)
        if (hook is! Map ||
            !_isManagedCommand(
              Map<String, Object?>.from(hook)['command'] as String?,
              managedScriptFileNames,
            ))
          hook,
    ];
    if (nextHooks.isEmpty) {
      continue;
    }
    cleaned.add(<String, Object?>{...definition, 'hooks': nextHooks});
  }
  return cleaned;
}

bool _isManagedCommand(String? command, Set<String> managedScriptFileNames) {
  if (command == null) {
    return false;
  }
  return managedScriptFileNames.any(command.contains);
}

List<Map<String, Object?>> _dedupeHookDefinitions(
  List<Map<String, Object?>> definitions,
) {
  final seen = <String>{};
  return <Map<String, Object?>>[
    for (final definition in definitions)
      if (seen.add(jsonEncode(definition))) definition,
  ];
}

String _trustSignature(_CodexHookTrustEntry entry) {
  return jsonEncode(
    _canonicalize(<String, Object?>{
      'eventLabel': entry.eventLabel,
      'command': entry.command,
      'timeoutSec': entry.timeoutSec,
      'async': entry.async,
      'matcher': entry.matcher,
      'statusMessage': entry.statusMessage,
    }),
  );
}

String _computeTrustKey(_CodexHookTrustEntry entry) {
  return '${_canonicalTrustPath(entry.sourcePath)}:${entry.eventLabel}:${entry.groupIndex}:${entry.handlerIndex}';
}

String _canonicalTrustPath(String sourcePath) {
  try {
    return File(sourcePath).resolveSymbolicLinksSync();
  } catch (_) {
    return sourcePath;
  }
}

String _computeTrustedHash(_CodexHookTrustEntry entry) {
  final handler = <String, Object?>{
    'type': 'command',
    'command': entry.command,
    'timeout': entry.timeoutSec == null
        ? 600
        : entry.timeoutSec!.clamp(1, 1 << 31),
    'async': entry.async ?? false,
    if (entry.statusMessage != null) 'statusMessage': entry.statusMessage,
  };
  final identity = <String, Object?>{
    'event_name': entry.eventLabel,
    'hooks': <Object?>[handler],
    if (entry.matcher != null) 'matcher': entry.matcher,
  };
  final serialized = jsonEncode(_canonicalize(identity));
  return 'sha256:${sha256.convert(utf8.encode(serialized))}';
}

Object? _canonicalize(Object? value) {
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalize(item)];
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return <String, Object?>{
      for (final entry in entries)
        entry.key.toString(): _canonicalize(entry.value),
    };
  }
  return value;
}

_ParsedTrustKey? _parseTrustKey(String key) {
  final lastColon = key.lastIndexOf(':');
  if (lastColon < 0) {
    return null;
  }
  final secondLast = key.lastIndexOf(':', lastColon - 1);
  if (secondLast < 0) {
    return null;
  }
  final thirdLast = key.lastIndexOf(':', secondLast - 1);
  if (thirdLast < 0) {
    return null;
  }
  final sourcePath = key.substring(0, thirdLast);
  if (sourcePath.isEmpty) {
    return null;
  }
  return _ParsedTrustKey(sourcePath: sourcePath);
}

@visibleForTesting
String computeCodexTrustedHashForTesting({
  required String sourcePath,
  required String eventLabel,
  required int groupIndex,
  required int handlerIndex,
  required String command,
  int? timeoutSec,
  bool? async,
  String? matcher,
  String? statusMessage,
}) {
  return _computeTrustedHash(
    _CodexHookTrustEntry(
      sourcePath: sourcePath,
      eventLabel: eventLabel,
      groupIndex: groupIndex,
      handlerIndex: handlerIndex,
      command: command,
      timeoutSec: timeoutSec,
      async: async,
      matcher: matcher,
      statusMessage: statusMessage,
    ),
  );
}

String _escapeTomlString(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\b', r'\b')
      .replaceAll('\f', r'\f')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

String _unescapeTomlString(String escaped) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < escaped.length) {
    final char = escaped[index];
    if (char == r'\' && index + 1 < escaped.length) {
      final next = escaped[index + 1];
      buffer.write(switch (next) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'b' => '\b',
        'f' => '\f',
        '"' => '"',
        r'\' => r'\',
        _ => '\\$next',
      });
      index += 2;
      continue;
    }
    buffer.write(char);
    index += 1;
  }
  return buffer.toString();
}

String _readTextFile(String path) {
  final raw = File(path).readAsStringSync();
  return raw.isNotEmpty && raw.codeUnitAt(0) == 0xfeff ? raw.substring(1) : raw;
}

void _writeTextAtomically(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  if (file.existsSync() && file.readAsStringSync() == contents) {
    return;
  }
  if (file.existsSync()) {
    file.copySync('$path.bak');
  }
  final tmp = File(
    p.join(file.parent.path, '.${DateTime.now().microsecondsSinceEpoch}.tmp'),
  )..writeAsStringSync(contents);
  tmp.renameSync(path);
}

List<_TomlSection> _tomlSections(String config) {
  final lines = config.split('\n');
  final sections = <_TomlSection>[];
  var start = -1;
  var header = '';
  var multilineState = const _TomlMultilineState();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final nextHeader = _isInsideTomlMultilineString(multilineState)
        ? null
        : _tomlTableHeader(line);
    if (nextHeader == null) {
      multilineState = _updateTomlMultilineState(multilineState, line);
      continue;
    }
    if (start >= 0) {
      sections.add(
        _TomlSection(
          header: header,
          block: lines.sublist(start, index).join('\n'),
          start: start,
        ),
      );
    }
    start = index;
    header = nextHeader;
    multilineState = _updateTomlMultilineState(multilineState, line);
  }
  if (start >= 0) {
    sections.add(
      _TomlSection(
        header: header,
        block: lines.sublist(start).join('\n'),
        start: start,
      ),
    );
  }
  return sections;
}

bool _isHookStateSection(String header) =>
    header.trimLeft().startsWith('[hooks.state.');

bool _isProjectSection(String header) =>
    header.trimLeft().startsWith('[projects.');

String _sectionHeaderKey(String header) => header.trim();

String _joinTomlBlocks(List<String> blocks) {
  final normalized = <String>[
    for (final block in blocks)
      if (block.trim().isNotEmpty) block.trimRight(),
  ];
  if (normalized.isEmpty) {
    return '';
  }
  return '${normalized.join('\n\n')}\n';
}

int _findNextTableHeader(String text) {
  var cursor = 0;
  var multilineState = const _TomlMultilineState();
  while (cursor < text.length) {
    final newlineIndex = text.indexOf('\n', cursor);
    final lineEnd = newlineIndex < 0 ? text.length : newlineIndex;
    final line = text
        .substring(cursor, lineEnd)
        .replaceFirst(RegExp(r'\r$'), '');
    if (!_isInsideTomlMultilineString(multilineState) &&
        _tomlTableHeader(line) != null) {
      return cursor;
    }
    multilineState = _updateTomlMultilineState(multilineState, line);
    if (newlineIndex < 0) {
      return -1;
    }
    cursor = newlineIndex + 1;
  }
  return -1;
}

String? _tomlTableHeader(String line) {
  final normalized = line.replaceFirst(RegExp(r'\r$'), '');
  final trimmedLeft = normalized.trimLeft();
  final leadingLength = normalized.length - trimmedLeft.length;
  final headerEnd = _tomlTableHeaderEnd(trimmedLeft);
  if (headerEnd == null) {
    return null;
  }
  return normalized.substring(0, leadingLength + headerEnd).trimRight();
}

int? _tomlTableHeaderEnd(String line) {
  if (!line.startsWith('[')) {
    return null;
  }
  final isArrayHeader = line.startsWith('[[');
  var index = isArrayHeader ? 2 : 1;
  var inBasicQuote = false;
  var inLiteralQuote = false;
  while (index < line.length) {
    final char = line[index];
    if (inBasicQuote) {
      if (char == r'\' && index + 1 < line.length) {
        index += 2;
        continue;
      }
      if (char == '"') {
        inBasicQuote = false;
      }
      index += 1;
      continue;
    }
    if (inLiteralQuote) {
      if (char == "'") {
        inLiteralQuote = false;
      }
      index += 1;
      continue;
    }
    if (char == '"') {
      inBasicQuote = true;
      index += 1;
      continue;
    }
    if (char == "'") {
      inLiteralQuote = true;
      index += 1;
      continue;
    }
    if (char == ']') {
      if (isArrayHeader) {
        if (line.length <= index + 1 || line[index + 1] != ']') {
          return null;
        }
        final tail = line.substring(index + 2);
        return RegExp(r'^\s*(#.*)?$').hasMatch(tail) ? index + 2 : null;
      }
      final tail = line.substring(index + 1);
      return RegExp(r'^\s*(#.*)?$').hasMatch(tail) ? index + 1 : null;
    }
    index += 1;
  }
  return null;
}

bool _isInsideTomlMultilineString(_TomlMultilineState state) {
  return state.basic || state.literal;
}

_TomlMultilineState _updateTomlMultilineState(
  _TomlMultilineState state,
  String line,
) {
  var mode = state.basic
      ? _TomlMultilineMode.basic
      : state.literal
      ? _TomlMultilineMode.literal
      : _TomlMultilineMode.none;
  var index = 0;
  while (index < line.length) {
    if (mode == _TomlMultilineMode.basic) {
      if (line[index] == r'\' && index + 1 < line.length) {
        index += 2;
        continue;
      }
      if (line.startsWith('"""', index)) {
        mode = _TomlMultilineMode.none;
        index += 3;
        continue;
      }
      index += 1;
      continue;
    }
    if (mode == _TomlMultilineMode.literal) {
      if (line.startsWith("'''", index)) {
        mode = _TomlMultilineMode.none;
        index += 3;
        continue;
      }
      index += 1;
      continue;
    }

    final char = line[index];
    if (char == '#') {
      break;
    }
    if (line.startsWith('"""', index)) {
      mode = _TomlMultilineMode.basic;
      index += 3;
      continue;
    }
    if (line.startsWith("'''", index)) {
      mode = _TomlMultilineMode.literal;
      index += 3;
      continue;
    }
    if (char == '"') {
      index = _skipTomlBasicString(line, index + 1);
      continue;
    }
    if (char == "'") {
      index = _skipTomlLiteralString(line, index + 1);
      continue;
    }
    index += 1;
  }
  return _TomlMultilineState(
    basic: mode == _TomlMultilineMode.basic,
    literal: mode == _TomlMultilineMode.literal,
  );
}

int _skipTomlBasicString(String line, int startIndex) {
  var index = startIndex;
  while (index < line.length) {
    final char = line[index];
    if (char == r'\' && index + 1 < line.length) {
      index += 2;
      continue;
    }
    if (char == '"') {
      return index + 1;
    }
    index += 1;
  }
  return index;
}

int _skipTomlLiteralString(String line, int startIndex) {
  final endIndex = line.indexOf("'", startIndex);
  return endIndex < 0 ? line.length : endIndex + 1;
}

String _shQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _resolveHome(Map<String, String>? environment) {
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

void _createResourceLink({
  required String sourcePath,
  required String targetPath,
}) {
  Link(targetPath).createSync(sourcePath, recursive: true);
}

String _fileSystemEntityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.link) {
    return 'link';
  }
  if (type == FileSystemEntityType.notFound) {
    return 'notFound';
  }
  return type.toString();
}

final class _TomlSection {
  const _TomlSection({
    required this.header,
    required this.block,
    required this.start,
  });

  final String header;
  final String block;
  final int start;
}

enum _TomlMultilineMode { none, basic, literal }

final class _TomlMultilineState {
  const _TomlMultilineState({this.basic = false, this.literal = false});

  final bool basic;
  final bool literal;
}
