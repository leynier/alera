import 'dart:io';

import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

class AiTextDiffOnlyExecution {
  const AiTextDiffOnlyExecution({
    required this.arguments,
    required this.environment,
  });

  final List<String> arguments;
  final Map<String, String> environment;
}

bool supportsDiffOnlyAiTextAgent(AiTextGenerationAgent agent) {
  return switch (aiTextAgentSpecs[agent]?.diffOnlyAccess) {
    AiTextDiffOnlyAccess.toolFree ||
    AiTextDiffOnlyAccess.codexRestrictedFilesystem => true,
    AiTextDiffOnlyAccess.unsupported || null => false,
  };
}

List<AiTextGenerationAgent> get diffOnlyAiTextAgents => aiTextAgentSpecs.values
    .where((spec) => spec.diffOnlyAccess != AiTextDiffOnlyAccess.unsupported)
    .map((spec) => spec.agent)
    .toList(growable: false);

Set<AiTextGenerationAgent> aiTextAgentsForModelDiscovery(
  AiTextGenerationSettings settings,
  Iterable<AiTextGenerationOperation> operations,
) => <AiTextGenerationAgent>{
  settings.agent,
  for (final operation in operations)
    operation == AiTextGenerationOperation.readingDiff
        ? readingDiffAgentForSettings(settings)
        : settings.agentFor(operation),
};

AiTextGenerationAgent readingDiffAgentForSettings(
  AiTextGenerationSettings settings,
) {
  final prompt = settings.promptSettingsFor(
    AiTextGenerationOperation.readingDiff,
  );
  final configured = prompt.agent ?? settings.agent;
  if (supportsDiffOnlyAiTextAgent(configured)) {
    return configured;
  }
  return AiTextGenerationAgent.codex;
}

String? readingDiffModelForSettings(
  AiTextGenerationSettings settings,
  AiTextGenerationAgent agent,
) {
  final prompt = settings.promptSettingsFor(
    AiTextGenerationOperation.readingDiff,
  );
  final configuredAgent = prompt.agent ?? settings.agent;
  if (configuredAgent != agent) {
    return settings.modelFor(agent);
  }
  return prompt.model ?? settings.modelFor(agent);
}

void requireDiffOnlyAiTextAgent(AiTextGenerationAgent agent) {
  if (supportsDiffOnlyAiTextAgent(agent)) {
    return;
  }
  final supported = diffOnlyAiTextAgents.map((agent) => agent.label).join(', ');
  throw AiTextGenerationException(
    '${agent.label} cannot guarantee diff-only access. Choose one of: $supported.',
  );
}

AiTextDiffOnlyExecution planDiffOnlyAiTextExecution({
  required AiTextAgentSpec spec,
  required List<String> arguments,
  required Map<String, String> environment,
  String? codexAuthCredentialsStore,
}) {
  switch (spec.diffOnlyAccess) {
    case AiTextDiffOnlyAccess.unsupported:
      requireDiffOnlyAiTextAgent(spec.agent);
      throw StateError('Unreachable diff-only agent policy.');
    case AiTextDiffOnlyAccess.toolFree:
      return AiTextDiffOnlyExecution(
        arguments: <String>[...arguments, ...spec.diffOnlyArgs],
        environment: environment,
      );
    case AiTextDiffOnlyAccess.codexRestrictedFilesystem:
      return AiTextDiffOnlyExecution(
        arguments: _codexDiffOnlyArguments(
          arguments,
          authCredentialsStore: codexAuthCredentialsStore,
        ),
        environment: _codexSubscriptionEnvironment(environment),
      );
  }
}

Future<String?> codexAuthCredentialsStore(
  Map<String, String> environment,
) async {
  final configuredHome = environment['CODEX_HOME']?.trim();
  final userHome = (environment['HOME'] ?? environment['USERPROFILE'])?.trim();
  final codexHome = configuredHome != null && configuredHome.isNotEmpty
      ? configuredHome
      : userHome != null && userHome.isNotEmpty
      ? p.join(userHome, '.codex')
      : null;
  if (codexHome == null) {
    return null;
  }
  try {
    final file = File(p.join(codexHome, 'config.toml'));
    if (!await file.exists()) {
      return null;
    }
    final document = TomlDocument.parse(await file.readAsString()).toMap();
    final value = document['cli_auth_credentials_store'];
    return value is String && _codexAuthCredentialStores.contains(value)
        ? value
        : null;
  } catch (_) {
    // Invalid or unreadable user configuration must not expose more of it to
    // the isolated process. Codex's default file store remains the fallback.
    return null;
  }
}

const Set<String> _codexAuthCredentialStores = <String>{
  'auto',
  'file',
  'keyring',
};

List<String> _codexDiffOnlyArguments(
  List<String> arguments, {
  required String? authCredentialsStore,
}) {
  final secured = List<String>.from(arguments);
  final sandboxIndex = secured.indexOf('-s');
  if (sandboxIndex >= 0 && sandboxIndex + 1 < secured.length) {
    secured.removeRange(sandboxIndex, sandboxIndex + 2);
  }
  secured.addAll(<String>[
    '--ignore-user-config',
    '--ignore-rules',
    '--strict-config',
    if (authCredentialsStore != null) ...<String>[
      '-c',
      'cli_auth_credentials_store="$authCredentialsStore"',
    ],
    '-c',
    'default_permissions="alera_diff_only"',
    '-c',
    'permissions.alera_diff_only={filesystem={":minimal"="read",":workspace_roots"="read"},network={enabled=false}}',
    '-c',
    'approval_policy="never"',
    '-c',
    'shell_environment_policy.inherit="none"',
    '-c',
    'web_search="disabled"',
    if (Platform.isWindows) ...<String>['-c', 'windows.sandbox="elevated"'],
    for (final feature in _disabledCodexDiffOnlyFeatures) ...<String>[
      '--disable',
      feature,
    ],
  ]);
  return secured;
}

const List<String> _disabledCodexDiffOnlyFeatures = <String>[
  'apps',
  'browser_use',
  'browser_use_external',
  'browser_use_full_cdp_access',
  'computer_use',
  'hooks',
  'image_generation',
  'in_app_browser',
  'memories',
  'multi_agent',
  'plugins',
  'remote_plugin',
  'skill_search',
  'tool_suggest',
  'view_image',
];

Map<String, String> _codexSubscriptionEnvironment(
  Map<String, String> environment,
) {
  return <String, String>{
    for (final entry in environment.entries)
      if (codexDiffOnlyEnvironmentVariableNames.contains(entry.key))
        entry.key: entry.value,
  };
}

const Set<String> codexDiffOnlyEnvironmentVariableNames = <String>{
  'APPDATA',
  'ALL_PROXY',
  'CODEX_HOME',
  'CODEX_SQLITE_HOME',
  'COMSPEC',
  'DBUS_SESSION_BUS_ADDRESS',
  'GNOME_KEYRING_CONTROL',
  'HOME',
  'HTTPS_PROXY',
  'HTTP_PROXY',
  'LANG',
  'LC_ALL',
  'LOCALAPPDATA',
  'NO_COLOR',
  'NO_PROXY',
  'PATH',
  'PATHEXT',
  'Path',
  'SSL_CERT_DIR',
  'SSL_CERT_FILE',
  'SystemRoot',
  'TEMP',
  'TERM',
  'TMP',
  'TMPDIR',
  'TZ',
  'USERPROFILE',
  'WINDIR',
  'XDG_CACHE_HOME',
  'XDG_CONFIG_HOME',
  'XDG_DATA_HOME',
  'XDG_RUNTIME_DIR',
  'XDG_STATE_HOME',
  'all_proxy',
  'https_proxy',
  'http_proxy',
  'no_proxy',
};
