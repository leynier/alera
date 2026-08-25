import 'dart:convert';

import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';

part 'grok_ai_assist.dart';
part 'fx_ai_assist.dart';
part 'opencode_ai_assist.dart';
part 'claude_ai_assist.dart';
part 'ai_assist_model_labels.dart';
part 'ai_assist_output_capabilities.dart';

enum AiAssistDiffOnlyAccess { unsupported, toolFree, codexRestrictedFilesystem }

class AiThinkingLevel {
  const AiThinkingLevel({required this.id, required this.label});

  final String id;
  final String label;
}

class AiAssistModel {
  const AiAssistModel({
    required this.id,
    required this.label,
    this.thinkingLevels = const <AiThinkingLevel>[],
    this.defaultThinkingLevel,
  });

  final String id;
  final String label;
  final List<AiThinkingLevel> thinkingLevels;
  final String? defaultThinkingLevel;

  bool get supportsThinking => thinkingLevels.isNotEmpty;

  AiAssistDiscoveredModel toDiscovered() {
    return AiAssistDiscoveredModel(
      id: id,
      label: label,
      thinkingLevels: <AiAssistDiscoveredThinkingLevel>[
        for (final level in thinkingLevels)
          AiAssistDiscoveredThinkingLevel(id: level.id, label: level.label),
      ],
      defaultThinkingLevel: defaultThinkingLevel,
    );
  }
}

AiAssistModel modelFromDiscovered(AiAssistDiscoveredModel model) {
  return AiAssistModel(
    id: model.id,
    label: model.label,
    thinkingLevels: <AiThinkingLevel>[
      for (final level in model.thinkingLevels)
        AiThinkingLevel(id: level.id, label: level.label),
    ],
    defaultThinkingLevel: model.defaultThinkingLevel,
  );
}

class AiAssistAgentSpec {
  const AiAssistAgentSpec({
    required this.agent,
    required this.binary,
    required this.promptDelivery,
    required this.modelsCommand,
    required this.parseModels,
    required this.models,
    required this.defaultModelId,
    required this.buildArgs,
    this.modelCanInherit = false,
    this.nativeStructuredOutput = AiNativeStructuredOutput.none,
    this.supportsRepositoryRead = false,
    this.readOnlyGuarantee = false,
    this.diffOnlyAccess = AiAssistDiffOnlyAccess.unsupported,
    this.diffOnlyArgs = const <String>[],
    this.maxPromptBytes = 1024 * 1024,
  });

  final AiAssistAgent agent;
  final String binary;
  final AiPromptDelivery promptDelivery;
  final List<String>? modelsCommand;
  final List<AiAssistModel> Function(String stdout) parseModels;
  final List<AiAssistModel> models;
  final String? defaultModelId;
  final bool modelCanInherit;
  final AiNativeStructuredOutput nativeStructuredOutput;
  final bool supportsRepositoryRead;
  final bool readOnlyGuarantee;
  final AiAssistDiffOnlyAccess diffOnlyAccess;
  final List<String> diffOnlyArgs;
  final int maxPromptBytes;
  final List<String> Function({
    required String prompt,
    required String model,
    String? thinkingLevel,
    required int timeoutSeconds,
  })
  buildArgs;

  String get label => agent.label;
}

const List<AiThinkingLevel> basicThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
];

const List<AiThinkingLevel> openAiThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
  AiThinkingLevel(id: 'xhigh', label: 'Extra High'),
];

const List<AiThinkingLevel> claudeThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
  AiThinkingLevel(id: 'xhigh', label: 'Extra High'),
  AiThinkingLevel(id: 'max', label: 'Max'),
];

const List<AiThinkingLevel> onOffThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'on', label: 'On'),
  AiThinkingLevel(id: 'off', label: 'Off'),
];

final Map<AiAssistAgent, AiAssistAgentSpec>
aiAssistAgentSpecs = <AiAssistAgent, AiAssistAgentSpec>{
  AiAssistAgent.claude: claudeAiAssistAgentSpec,
  AiAssistAgent.codex: AiAssistAgentSpec(
    agent: AiAssistAgent.codex,
    binary: 'codex',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['debug', 'models'],
    parseModels: parseCodexModels,
    models: const <AiAssistModel>[
      AiAssistModel(
        id: 'gpt-5.5',
        label: 'GPT-5.5',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiAssistModel(
        id: 'gpt-5.4',
        label: 'GPT-5.4',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiAssistModel(
        id: 'gpt-5.4-mini',
        label: 'GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'gpt-5.5',
    nativeStructuredOutput: AiNativeStructuredOutput.codexSchemaFile,
    supportsRepositoryRead: true,
    readOnlyGuarantee: true,
    diffOnlyAccess: AiAssistDiffOnlyAccess.codexRestrictedFilesystem,
    maxPromptBytes: 1024 * 1024,
    buildArgs:
        ({
          required model,
          thinkingLevel,
          required prompt,
          required timeoutSeconds,
        }) => <String>[
          'exec',
          '--ephemeral',
          '--skip-git-repo-check',
          '-s',
          'read-only',
          '--model',
          model,
          if (thinkingLevel != null) '-c' else '',
          if (thinkingLevel != null) 'model_reasoning_effort=$thinkingLevel',
        ].where((arg) => arg.isNotEmpty).toList(growable: false),
  ),
  AiAssistAgent.copilot: AiAssistAgentSpec(
    agent: AiAssistAgent.copilot,
    binary: 'copilot',
    promptDelivery: AiPromptDelivery.argv,
    modelsCommand: null,
    parseModels: parseLineModels,
    models: const <AiAssistModel>[
      AiAssistModel(id: 'auto', label: 'Auto'),
      AiAssistModel(
        id: 'gpt-5.4',
        label: 'GPT-5.4',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiAssistModel(
        id: 'gpt-5.4-mini',
        label: 'GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'gpt-5.4',
    diffOnlyAccess: AiAssistDiffOnlyAccess.toolFree,
    diffOnlyArgs: const <String>[
      '--available-tools=',
      '--excluded-tools=*',
      '--disable-builtin-mcps',
      '--no-ask-user',
      '--no-auto-update',
    ],
    maxPromptBytes: 24000,
    buildArgs:
        ({
          required prompt,
          required model,
          thinkingLevel,
          required timeoutSeconds,
        }) => <String>[
          '--prompt',
          prompt,
          '--silent',
          '--stream',
          'off',
          '--no-custom-instructions',
          '--model',
          model,
          if (thinkingLevel != null) ...<String>['--effort', thinkingLevel],
        ],
  ),
  AiAssistAgent.cursor: AiAssistAgentSpec(
    agent: AiAssistAgent.cursor,
    binary: 'cursor-agent',
    promptDelivery: AiPromptDelivery.argv,
    modelsCommand: const <String>['--list-models'],
    parseModels: parseCursorModels,
    models: const <AiAssistModel>[AiAssistModel(id: 'auto', label: 'Auto')],
    defaultModelId: 'auto',
    maxPromptBytes: 24000,
    buildArgs:
        ({
          required prompt,
          required model,
          thinkingLevel,
          required timeoutSeconds,
        }) => <String>[
          '--print',
          '--mode',
          'ask',
          '--trust',
          '--output-format',
          'text',
          '--model',
          model,
          prompt,
        ],
  ),
  AiAssistAgent.agy: AiAssistAgentSpec(
    agent: AiAssistAgent.agy,
    binary: 'agy',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['models'],
    parseModels: parseAgyModels,
    models: const <AiAssistModel>[],
    defaultModelId: null,
    modelCanInherit: true,
    nativeStructuredOutput: AiNativeStructuredOutput.jsonSchemaArgument,
    buildArgs:
        ({
          required model,
          thinkingLevel,
          required prompt,
          required timeoutSeconds,
        }) => <String>[
          '--print',
          '--sandbox',
          '--print-timeout',
          '${timeoutSeconds}s',
          if (model.trim().isNotEmpty) ...<String>['--model', model],
        ],
  ),
  AiAssistAgent.opencode: openCodeAiAssistSpec(
    agent: AiAssistAgent.opencode,
    binary: 'opencode',
  ),
  AiAssistAgent.opencode2: openCodeAiAssistSpec(
    agent: AiAssistAgent.opencode2,
    binary: 'opencode2',
  ),
  AiAssistAgent.pi: AiAssistAgentSpec(
    agent: AiAssistAgent.pi,
    binary: 'pi',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['--list-models'],
    parseModels: parsePiModels,
    models: const <AiAssistModel>[
      AiAssistModel(
        id: 'github-copilot/gpt-5.4-mini',
        label: 'GitHub Copilot GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'github-copilot/gpt-5.4-mini',
    diffOnlyAccess: AiAssistDiffOnlyAccess.toolFree,
    buildArgs:
        ({
          required model,
          thinkingLevel,
          required prompt,
          required timeoutSeconds,
        }) => <String>[
          '--print',
          '--no-session',
          '--no-tools',
          '--no-extensions',
          '--no-skills',
          '--no-context-files',
          '--mode',
          'text',
          '--model',
          model,
          if (thinkingLevel != null) ...<String>['--thinking', thinkingLevel],
        ],
  ),
  AiAssistAgent.amp: AiAssistAgentSpec(
    agent: AiAssistAgent.amp,
    binary: 'amp',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: null,
    parseModels: parseLineModels,
    models: const <AiAssistModel>[
      AiAssistModel(id: 'smart', label: 'Smart'),
      AiAssistModel(id: 'rush', label: 'Rush'),
      AiAssistModel(
        id: 'large',
        label: 'Large',
        thinkingLevels: basicThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiAssistModel(
        id: 'deep',
        label: 'Deep',
        thinkingLevels: basicThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'smart',
    buildArgs:
        ({
          required model,
          thinkingLevel,
          required prompt,
          required timeoutSeconds,
        }) => <String>[
          '--execute',
          '--no-notifications',
          '--no-ide',
          '--no-jetbrains',
          '--mode',
          model,
          if (thinkingLevel != null) ...<String>['--effort', thinkingLevel],
        ],
  ),
  AiAssistAgent.grok: grokAiAssistAgentSpec,
  AiAssistAgent.fx: fxAiAssistAgentSpec,
};

List<AiAssistModel> discoveredModelsForAgent(
  AiAssistSettings settings,
  AiAssistAgent agent,
) {
  return settings
      .discoveredModelsFor(agent)
      .map(modelFromDiscovered)
      .toList(growable: false);
}

List<AiAssistModel> modelsForAgent(
  AiAssistAgent agent,
  AiAssistSettings settings,
) {
  final spec = aiAssistAgentSpecs[agent];
  if (spec == null) {
    return const <AiAssistModel>[];
  }
  return _uniqueModels(<AiAssistModel>[
    if (spec.modelCanInherit)
      const AiAssistModel(id: '', label: 'Agent Default'),
    ...discoveredModelsForAgent(settings, agent),
    ...spec.models,
  ]);
}

String defaultModelIdForAgent(AiAssistAgent agent, AiAssistSettings settings) {
  final spec = aiAssistAgentSpecs[agent];
  if (spec == null) {
    return 'custom';
  }
  if (!spec.modelCanInherit) {
    final discoveredDefault = settings.discoveredDefaultModelFor(agent);
    if (discoveredDefault != null) {
      return discoveredDefault;
    }
  }
  return spec.defaultModelId ?? '';
}

AiAssistModel modelForAgent(
  AiAssistAgent agent,
  String? modelId, {
  List<AiAssistModel> extraModels = const <AiAssistModel>[],
}) {
  final spec = aiAssistAgentSpecs[agent];
  if (spec == null) {
    return const AiAssistModel(id: 'custom', label: 'Custom');
  }
  final id = modelId?.trim().isNotEmpty == true
      ? modelId!.trim()
      : spec.defaultModelId ?? '';
  if (id.isEmpty && spec.modelCanInherit) {
    return const AiAssistModel(id: '', label: 'Agent Default');
  }
  return <AiAssistModel>[...extraModels, ...spec.models].firstWhere(
    (model) => model.id == id,
    orElse: () => AiAssistModel(id: id, label: labelFromModelId(id)),
  );
}

List<AiAssistModel> parseLineModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => AiAssistModel(id: line, label: labelFromModelId(line)))
        .toList(growable: false),
  );
}

List<AiAssistModel> parseAgyModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .map((line) => line.replaceFirst(RegExp(r'^[*-]\s+'), ''))
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.toLowerCase().startsWith('available model'),
        )
        .map(
          (line) => AiAssistModel(id: line, label: labelFromAgyModelId(line)),
        )
        .toList(growable: false),
  );
}

List<AiAssistModel> parseCursorModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => RegExp(r'^([^\s]+)\s+-\s+(.+)$').firstMatch(line.trim()))
        .whereType<RegExpMatch>()
        .map(
          (match) => AiAssistModel(
            id: match.group(1)!,
            label: match
                .group(2)!
                .replaceFirst(
                  RegExp(r'\s+\((?:default|current)\)$', caseSensitive: false),
                  '',
                ),
          ),
        )
        .toList(growable: false),
  );
}

List<AiAssistModel> parseCodexModels(String stdout) {
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is! Map) {
      return const <AiAssistModel>[];
    }
    final models = decoded['models'];
    if (models is! List) {
      return const <AiAssistModel>[];
    }
    return _uniqueModels(
      models
          .whereType<Map>()
          .map((item) {
            final slug = item['slug'];
            final label = item['display_name'];
            return slug is String && label is String
                ? AiAssistModel(
                    id: slug,
                    label: label,
                    thinkingLevels: openAiThinkingLevels,
                    defaultThinkingLevel:
                        item['default_reasoning_level'] is String
                        ? item['default_reasoning_level'] as String
                        : 'low',
                  )
                : null;
          })
          .whereType<AiAssistModel>()
          .toList(growable: false),
    );
  } catch (_) {
    return const <AiAssistModel>[];
  }
}

List<AiAssistModel> parsePiModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((parts) => parts.length >= 2 && parts.first != 'provider')
        .map((parts) {
          final id = '${parts[0]}/${parts[1]}';
          return AiAssistModel(id: id, label: labelFromModelId(id));
        })
        .toList(growable: false),
  );
}

List<AiAssistModel> _uniqueModels(List<AiAssistModel> models) {
  final seen = <String>{};
  return models.where((model) => seen.add(model.id)).toList(growable: false);
}
