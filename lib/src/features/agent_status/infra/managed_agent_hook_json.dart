part of 'managed_agent_hook_installer.dart';

extension _ManagedAgentHookJson on ManagedAgentHookInstallService {
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

  // coverage:ignore-start
  // External PowerShell hook template. The Dart behavior around installing and
  // selecting this script is tested; executing every literal line belongs to
  // Windows agent-hook smoke coverage.
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
  // coverage:ignore-end

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
}
