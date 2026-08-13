part of 'ai_text_generation_registry.dart';

final AiTextAgentSpec claudeAiTextAgentSpec = AiTextAgentSpec(
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
  nativeStructuredOutput: AiNativeStructuredOutput.claudeJsonSchema,
  supportsRepositoryRead: true,
  readOnlyGuarantee: true,
  diffOnlyAccess: AiTextDiffOnlyAccess.toolFree,
  diffOnlyArgs: const <String>[
    '--safe-mode',
    '--disable-slash-commands',
    '--strict-mcp-config',
    '--mcp-config',
    '{"mcpServers":{}}',
    '--tools',
    '',
    '--no-chrome',
  ],
  maxPromptBytes: 1024 * 1024,
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
);
