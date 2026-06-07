import 'dart:convert';

import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';

enum AiPromptDelivery { argv, stdin }

class AiThinkingLevel {
  const AiThinkingLevel({required this.id, required this.label});

  final String id;
  final String label;
}

class AiTextModel {
  const AiTextModel({
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

  AiTextDiscoveredModel toDiscovered() {
    return AiTextDiscoveredModel(
      id: id,
      label: label,
      thinkingLevels: <AiTextDiscoveredThinkingLevel>[
        for (final level in thinkingLevels)
          AiTextDiscoveredThinkingLevel(id: level.id, label: level.label),
      ],
      defaultThinkingLevel: defaultThinkingLevel,
    );
  }
}

AiTextModel modelFromDiscovered(AiTextDiscoveredModel model) {
  return AiTextModel(
    id: model.id,
    label: model.label,
    thinkingLevels: <AiThinkingLevel>[
      for (final level in model.thinkingLevels)
        AiThinkingLevel(id: level.id, label: level.label),
    ],
    defaultThinkingLevel: model.defaultThinkingLevel,
  );
}

class AiTextAgentSpec {
  const AiTextAgentSpec({
    required this.agent,
    required this.binary,
    required this.promptDelivery,
    required this.modelsCommand,
    required this.parseModels,
    required this.models,
    required this.defaultModelId,
    required this.buildArgs,
  });

  final AiTextGenerationAgent agent;
  final String binary;
  final AiPromptDelivery promptDelivery;
  final List<String>? modelsCommand;
  final List<AiTextModel> Function(String stdout) parseModels;
  final List<AiTextModel> models;
  final String defaultModelId;
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
  AiThinkingLevel(id: 'xhigh', label: 'Extra high'),
];

const List<AiThinkingLevel> claudeThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
  AiThinkingLevel(id: 'xhigh', label: 'Extra high'),
  AiThinkingLevel(id: 'max', label: 'Max'),
];

const List<AiThinkingLevel> onOffThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'on', label: 'On'),
  AiThinkingLevel(id: 'off', label: 'Off'),
];

final Map<AiTextGenerationAgent, AiTextAgentSpec>
aiTextAgentSpecs = <AiTextGenerationAgent, AiTextAgentSpec>{
  AiTextGenerationAgent.claude: AiTextAgentSpec(
    agent: AiTextGenerationAgent.claude,
    binary: 'claude',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: null,
    parseModels: parseLineModels,
    models: const <AiTextModel>[
      AiTextModel(id: 'haiku', label: 'Haiku'),
      AiTextModel(
        id: 'sonnet',
        label: 'Sonnet',
        thinkingLevels: claudeThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiTextModel(
        id: 'opus',
        label: 'Opus',
        thinkingLevels: claudeThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'sonnet',
    buildArgs:
        ({
          required model,
          thinkingLevel,
          required prompt,
          required timeoutSeconds,
        }) => <String>[
          '-p',
          '--output-format',
          'text',
          '--model',
          model,
          '--permission-mode',
          'plan',
          if (thinkingLevel != null) ...<String>['--effort', thinkingLevel],
        ],
  ),
  AiTextGenerationAgent.codex: AiTextAgentSpec(
    agent: AiTextGenerationAgent.codex,
    binary: 'codex',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['debug', 'models'],
    parseModels: parseCodexModels,
    models: const <AiTextModel>[
      AiTextModel(
        id: 'gpt-5.5',
        label: 'GPT-5.5',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiTextModel(
        id: 'gpt-5.4',
        label: 'GPT-5.4',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiTextModel(
        id: 'gpt-5.4-mini',
        label: 'GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'gpt-5.5',
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
  AiTextGenerationAgent.copilot: AiTextAgentSpec(
    agent: AiTextGenerationAgent.copilot,
    binary: 'copilot',
    promptDelivery: AiPromptDelivery.argv,
    modelsCommand: null,
    parseModels: parseLineModels,
    models: const <AiTextModel>[
      AiTextModel(id: 'auto', label: 'Auto'),
      AiTextModel(
        id: 'gpt-5.4',
        label: 'GPT-5.4',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiTextModel(
        id: 'gpt-5.4-mini',
        label: 'GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'gpt-5.4',
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
  AiTextGenerationAgent.cursor: AiTextAgentSpec(
    agent: AiTextGenerationAgent.cursor,
    binary: 'cursor-agent',
    promptDelivery: AiPromptDelivery.argv,
    modelsCommand: const <String>['--list-models'],
    parseModels: parseCursorModels,
    models: const <AiTextModel>[AiTextModel(id: 'auto', label: 'Auto')],
    defaultModelId: 'auto',
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
  AiTextGenerationAgent.agy: AiTextAgentSpec(
    agent: AiTextGenerationAgent.agy,
    binary: 'agy',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['models'],
    parseModels: parseLineModels,
    models: const <AiTextModel>[
      AiTextModel(
        id: 'Gemini 3.5 Flash (Medium)',
        label: 'Gemini 3.5 Flash (Medium)',
      ),
      AiTextModel(
        id: 'Gemini 3.5 Flash (High)',
        label: 'Gemini 3.5 Flash (High)',
      ),
      AiTextModel(
        id: 'Gemini 3.5 Flash (Low)',
        label: 'Gemini 3.5 Flash (Low)',
      ),
    ],
    defaultModelId: 'Gemini 3.5 Flash (Medium)',
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
          '--model',
          model,
        ],
  ),
  AiTextGenerationAgent.opencode: AiTextAgentSpec(
    agent: AiTextGenerationAgent.opencode,
    binary: 'opencode',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['models'],
    parseModels: parseLineModels,
    models: const <AiTextModel>[
      AiTextModel(
        id: 'opencode/deepseek-v4-flash-free',
        label: 'OpenCode DeepSeek V4 Flash Free',
      ),
    ],
    defaultModelId: 'opencode/deepseek-v4-flash-free',
    buildArgs:
        ({
          required prompt,
          required model,
          thinkingLevel,
          required timeoutSeconds,
        }) => <String>[
          'run',
          '--model',
          model,
          '--agent',
          'build',
          '--format',
          'default',
          if (thinkingLevel != null) ...<String>['--variant', thinkingLevel],
        ],
  ),
  AiTextGenerationAgent.pi: AiTextAgentSpec(
    agent: AiTextGenerationAgent.pi,
    binary: 'pi',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['--list-models'],
    parseModels: parsePiModels,
    models: const <AiTextModel>[
      AiTextModel(
        id: 'github-copilot/gpt-5.4-mini',
        label: 'GitHub Copilot GPT-5.4 Mini',
        thinkingLevels: openAiThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
    ],
    defaultModelId: 'github-copilot/gpt-5.4-mini',
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
  AiTextGenerationAgent.amp: AiTextAgentSpec(
    agent: AiTextGenerationAgent.amp,
    binary: 'amp',
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: null,
    parseModels: parseLineModels,
    models: const <AiTextModel>[
      AiTextModel(id: 'smart', label: 'Smart'),
      AiTextModel(id: 'rush', label: 'Rush'),
      AiTextModel(
        id: 'large',
        label: 'Large',
        thinkingLevels: basicThinkingLevels,
        defaultThinkingLevel: 'low',
      ),
      AiTextModel(
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
};

List<AiTextModel> discoveredModelsForAgent(
  AiTextGenerationSettings settings,
  AiTextGenerationAgent agent,
) {
  return settings
      .discoveredModelsFor(agent)
      .map(modelFromDiscovered)
      .toList(growable: false);
}

List<AiTextModel> modelsForAgent(
  AiTextGenerationAgent agent,
  AiTextGenerationSettings settings,
) {
  final spec = aiTextAgentSpecs[agent];
  if (spec == null) {
    return const <AiTextModel>[];
  }
  return _uniqueModels(<AiTextModel>[
    ...discoveredModelsForAgent(settings, agent),
    ...spec.models,
  ]);
}

String defaultModelIdForAgent(
  AiTextGenerationAgent agent,
  AiTextGenerationSettings settings,
) {
  final spec = aiTextAgentSpecs[agent];
  if (spec == null) {
    return 'custom';
  }
  final discoveredDefault = settings.discoveredDefaultModelFor(agent);
  if (discoveredDefault != null) {
    return discoveredDefault;
  }
  return spec.defaultModelId;
}

AiTextModel modelForAgent(
  AiTextGenerationAgent agent,
  String? modelId, {
  List<AiTextModel> extraModels = const <AiTextModel>[],
}) {
  final spec = aiTextAgentSpecs[agent];
  if (spec == null) {
    return const AiTextModel(id: 'custom', label: 'Custom');
  }
  final id = modelId?.trim().isNotEmpty == true
      ? modelId!.trim()
      : spec.defaultModelId;
  return <AiTextModel>[...extraModels, ...spec.models].firstWhere(
    (model) => model.id == id,
    orElse: () => AiTextModel(id: id, label: labelFromModelId(id)),
  );
}

List<AiTextModel> parseLineModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => AiTextModel(id: line, label: labelFromModelId(line)))
        .toList(growable: false),
  );
}

List<AiTextModel> parseCursorModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => RegExp(r'^([^\s]+)\s+-\s+(.+)$').firstMatch(line.trim()))
        .whereType<RegExpMatch>()
        .map(
          (match) => AiTextModel(
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

List<AiTextModel> parseCodexModels(String stdout) {
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is! Map) {
      return const <AiTextModel>[];
    }
    final models = decoded['models'];
    if (models is! List) {
      return const <AiTextModel>[];
    }
    return _uniqueModels(
      models
          .whereType<Map>()
          .map((item) {
            final slug = item['slug'];
            final label = item['display_name'];
            return slug is String && label is String
                ? AiTextModel(
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
          .whereType<AiTextModel>()
          .toList(growable: false),
    );
  } catch (_) {
    return const <AiTextModel>[];
  }
}

List<AiTextModel> parsePiModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((parts) => parts.length >= 2 && parts.first != 'provider')
        .map((parts) {
          final id = '${parts[0]}/${parts[1]}';
          return AiTextModel(id: id, label: labelFromModelId(id));
        })
        .toList(growable: false),
  );
}

String labelFromModelId(String id) {
  return id
      .split(RegExp(r'[/-]'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.toLowerCase() == 'gpt') {
          return 'GPT';
        }
        if (part.length <= 3 && RegExp(r'^\d').hasMatch(part)) {
          return part.toUpperCase();
        }
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

List<AiTextModel> _uniqueModels(List<AiTextModel> models) {
  final seen = <String>{};
  return models.where((model) => seen.add(model.id)).toList(growable: false);
}
