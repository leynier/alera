part of 'ai_text_generation_registry.dart';

const List<AiThinkingLevel> grokThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'default', label: 'Grok Default'),
  AiThinkingLevel(id: 'none', label: 'None'),
  AiThinkingLevel(id: 'minimal', label: 'Minimal'),
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
  AiThinkingLevel(id: 'xhigh', label: 'Extra High'),
];

final AiTextAgentSpec grokAiTextAgentSpec = AiTextAgentSpec(
  agent: AiTextGenerationAgent.grok,
  binary: 'grok',
  promptDelivery: AiPromptDelivery.promptFile,
  modelsCommand: const <String>['models'],
  parseModels: parseGrokModels,
  models: const <AiTextModel>[
    AiTextModel(
      id: 'grok-4.5',
      label: 'Grok 4.5',
      thinkingLevels: grokThinkingLevels,
      defaultThinkingLevel: 'default',
    ),
  ],
  defaultModelId: 'grok-4.5',
  nativeStructuredOutput: AiNativeStructuredOutput.jsonSchemaArgument,
  diffOnlyAccess: AiTextDiffOnlyAccess.toolFree,
  buildArgs:
      ({
        required model,
        thinkingLevel,
        required prompt,
        required timeoutSeconds,
      }) => <String>[
        '--prompt-file',
        prompt,
        '--output-format',
        'plain',
        '--model',
        model,
        '--tools',
        '',
        '--no-subagents',
        '--disable-web-search',
        '--no-memory',
        '--max-turns',
        '1',
        '--verbatim',
        if (thinkingLevel != null && thinkingLevel != 'default') ...<String>[
          '--effort',
          thinkingLevel,
        ],
      ],
);

List<AiTextModel> parseGrokModels(String stdout) {
  return _uniqueModels(
    stdout
        .split(RegExp(r'\r?\n'))
        .map(
          (line) => RegExp(
            r'^\s*[*-]\s+([^\s]+)(?:\s+\(default\))?\s*$',
            caseSensitive: false,
          ).firstMatch(line),
        )
        .whereType<RegExpMatch>()
        .map((match) {
          final id = match.group(1)!;
          return AiTextModel(
            id: id,
            label: labelFromModelId(id),
            thinkingLevels: grokThinkingLevels,
            defaultThinkingLevel: 'default',
          );
        })
        .toList(growable: false),
  );
}
