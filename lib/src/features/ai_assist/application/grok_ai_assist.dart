part of 'ai_assist_registry.dart';

const List<AiThinkingLevel> grokThinkingLevels = <AiThinkingLevel>[
  AiThinkingLevel(id: 'default', label: 'Grok Default'),
  AiThinkingLevel(id: 'none', label: 'None'),
  AiThinkingLevel(id: 'minimal', label: 'Minimal'),
  AiThinkingLevel(id: 'low', label: 'Low'),
  AiThinkingLevel(id: 'medium', label: 'Medium'),
  AiThinkingLevel(id: 'high', label: 'High'),
  AiThinkingLevel(id: 'xhigh', label: 'Extra High'),
  AiThinkingLevel(id: 'max', label: 'Max'),
];

final AiAssistAgentSpec grokAiAssistAgentSpec = AiAssistAgentSpec(
  agent: .grok,
  binary: 'grok',
  promptDelivery: .promptFile,
  modelsCommand: const <String>['models'],
  parseModels: parseGrokModels,
  models: const <AiAssistModel>[
    AiAssistModel(
      id: 'grok-4.6',
      label: 'Grok 4.6',
      thinkingLevels: grokThinkingLevels,
      defaultThinkingLevel: 'default',
    ),
  ],
  defaultModelId: 'grok-4.6',
  nativeStructuredOutput: .jsonSchemaArgument,
  diffOnlyAccess: .toolFree,
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

List<AiAssistModel> parseGrokModels(String stdout) {
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
          return AiAssistModel(
            id: id,
            label: labelFromModelId(id),
            thinkingLevels: grokThinkingLevels,
            defaultThinkingLevel: 'default',
          );
        })
        .toList(growable: false),
  );
}
