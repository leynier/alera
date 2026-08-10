import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes every operation label and agent mapping', () {
    expect(
      AiTextGenerationOperation.values.map((operation) => operation.label),
      <String>[
        'Commit Messages',
        'Pull Request Details',
        'Branch Names',
        'Reading Diffs',
        'Workspace Identity',
      ],
    );
    expect(AiTextGenerationAgent.codex.agentType, AgentType.codex);
    expect(AiTextGenerationAgent.claude.agentType, AgentType.claude);
    expect(AiTextGenerationAgent.copilot.agentType, AgentType.copilot);
    expect(AiTextGenerationAgent.cursor.agentType, AgentType.cursor);
    expect(AiTextGenerationAgent.agy.agentType, AgentType.agy);
    expect(AiTextGenerationAgent.opencode.agentType, AgentType.opencode);
    expect(AiTextGenerationAgent.opencode2.agentType, AgentType.opencode2);
    expect(AiTextGenerationAgent.pi.agentType, AgentType.pi);
    expect(AiTextGenerationAgent.amp.agentType, AgentType.amp);
    expect(AiTextGenerationAgent.grok.agentType, AgentType.grok);
    expect(AiTextGenerationAgent.custom.agentType, isNull);
    expect(
      AiTextGenerationAgent.values.map((agent) => agent.label),
      containsAll(<String>[
        'Codex',
        'Claude Code',
        'GitHub Copilot',
        'Cursor',
        'Antigravity',
        'OpenCode',
        'OpenCode 2',
        'Pi',
        'Amp',
        'Grok Build',
        'Custom Command',
      ]),
    );
  });

  test('round-trips settings through the generated mapper', () {
    const settings = AiTextGenerationSettings(
      agent: AiTextGenerationAgent.custom,
      customCommand: 'generate',
      selectedModelByAgent: <AiTextGenerationAgent, String>{
        AiTextGenerationAgent.codex: 'gpt-5',
      },
      selectedThinkingByOperation:
          <AiTextGenerationOperation, Map<String, String>>{
            AiTextGenerationOperation.commitMessage: <String, String>{
              'gpt-5': 'high',
            },
          },
      promptSettingsByOperation:
          <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
            AiTextGenerationOperation.commitMessage:
                AiTextGenerationPromptSettings(
                  agent: AiTextGenerationAgent.claude,
                  model: 'opus',
                ),
          },
    );

    expect(AiTextGenerationSettings.fromJson(settings.toMap()), settings);
  });

  test('resolves prompt agent and model overrides independently', () {
    const settings = AiTextGenerationSettings(
      agent: AiTextGenerationAgent.codex,
      selectedModelByAgent: <AiTextGenerationAgent, String>{
        AiTextGenerationAgent.codex: 'gpt-global',
        AiTextGenerationAgent.claude: 'sonnet',
        AiTextGenerationAgent.opencode: 'provider/reading-model',
      },
      promptSettingsByOperation:
          <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
            AiTextGenerationOperation.commitMessage:
                AiTextGenerationPromptSettings(
                  agent: AiTextGenerationAgent.claude,
                ),
            AiTextGenerationOperation.pullRequestDetails:
                AiTextGenerationPromptSettings(model: 'gpt-pull-request'),
            AiTextGenerationOperation.readingDiff:
                AiTextGenerationPromptSettings(
                  agent: AiTextGenerationAgent.opencode,
                ),
          },
    );

    expect(
      settings.agentFor(AiTextGenerationOperation.commitMessage),
      AiTextGenerationAgent.claude,
    );
    expect(
      settings.modelForOperation(AiTextGenerationOperation.commitMessage),
      'sonnet',
    );
    expect(
      settings.agentFor(AiTextGenerationOperation.pullRequestDetails),
      AiTextGenerationAgent.codex,
    );
    expect(
      settings.modelForOperation(AiTextGenerationOperation.pullRequestDetails),
      'gpt-pull-request',
    );
    expect(
      settings.agentFor(AiTextGenerationOperation.readingDiff),
      AiTextGenerationAgent.opencode,
    );
    expect(
      settings.modelForOperation(AiTextGenerationOperation.readingDiff),
      'provider/reading-model',
    );
    expect(
      settings.modelForOperation(AiTextGenerationOperation.workspaceIdentity),
      'gpt-global',
    );
  });

  test('keeps operation reasoning overrides isolated with global fallback', () {
    const settings = AiTextGenerationSettings(
      selectedThinkingByModel: <String, String>{'gpt-5.5': 'low'},
      selectedThinkingByOperation:
          <AiTextGenerationOperation, Map<String, String>>{
            AiTextGenerationOperation.commitMessage: <String, String>{
              'gpt-5.5': 'high',
            },
          },
    );

    expect(
      settings.thinkingForOperation(
        AiTextGenerationOperation.commitMessage,
        'gpt-5.5',
      ),
      'high',
    );
    expect(
      settings.thinkingForOperation(
        AiTextGenerationOperation.pullRequestDetails,
        'gpt-5.5',
      ),
      'low',
    );
  });

  test('reports whether prompt settings inherit each global value', () {
    const inherited = AiTextGenerationPromptSettings(model: '  ');
    const overridden = AiTextGenerationPromptSettings(
      agent: AiTextGenerationAgent.claude,
      model: 'sonnet',
    );

    expect(inherited.inheritsAgent, isTrue);
    expect(inherited.inheritsModel, isTrue);
    expect(overridden.inheritsAgent, isFalse);
    expect(overridden.inheritsModel, isFalse);
  });
}
