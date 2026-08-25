part of 'ai_assist_registry.dart';

final AiAssistAgentSpec claudeAiAssistAgentSpec = AiAssistAgentSpec(
  agent: AiAssistAgent.claude,
  binary: 'claude',
  promptDelivery: AiPromptDelivery.stdin,
  modelsCommand: null,
  parseModels: parseLineModels,
  models: const <AiAssistModel>[
    AiAssistModel(id: 'haiku', label: 'Haiku'),
    AiAssistModel(
      id: 'sonnet',
      label: 'Sonnet',
      thinkingLevels: claudeThinkingLevels,
      defaultThinkingLevel: 'low',
    ),
    AiAssistModel(
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
  diffOnlyAccess: AiAssistDiffOnlyAccess.toolFree,
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
