import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes every operation label and agent mapping', () {
    expect(
      AiAssistOperation.values.map((operation) => operation.label),
      <String>[
        'Commit Messages',
        'Pull Request Details',
        'Branch Names',
        'Reading Diffs',
        'Workspace Identity',
        'Agent Titles',
        'Speech Messages',
      ],
    );
    expect(AiAssistAgent.codex.agentType, AgentType.codex);
    expect(AiAssistAgent.claude.agentType, AgentType.claude);
    expect(AiAssistAgent.copilot.agentType, AgentType.copilot);
    expect(AiAssistAgent.cursor.agentType, AgentType.cursor);
    expect(AiAssistAgent.agy.agentType, AgentType.agy);
    expect(AiAssistAgent.opencode.agentType, AgentType.opencode);
    expect(AiAssistAgent.opencode2.agentType, AgentType.opencode2);
    expect(AiAssistAgent.pi.agentType, AgentType.pi);
    expect(AiAssistAgent.amp.agentType, AgentType.amp);
    expect(AiAssistAgent.grok.agentType, AgentType.grok);
    expect(AiAssistAgent.fx.agentType, AgentType.fx);
    expect(AiAssistAgent.custom.agentType, isNull);
    expect(
      AiAssistAgent.values.map((agent) => agent.label),
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
        'fx',
        'Custom Command',
      ]),
    );
  });

  test('round-trips settings through the generated mapper', () {
    const settings = AiAssistSettings(
      agent: AiAssistAgent.custom,
      customCommand: 'generate',
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.codex: 'gpt-5',
      },
      selectedThinkingByOperation: <AiAssistOperation, Map<String, String>>{
        AiAssistOperation.commitMessage: <String, String>{'gpt-5': 'high'},
      },
      promptSettingsByOperation: <AiAssistOperation, AiAssistPromptSettings>{
        AiAssistOperation.commitMessage: AiAssistPromptSettings(
          agent: AiAssistAgent.claude,
          model: 'opus',
        ),
      },
    );

    expect(AiAssistSettings.fromJson(settings.toMap()), settings);
  });

  test('resolves prompt agent and model overrides independently', () {
    const settings = AiAssistSettings(
      agent: AiAssistAgent.codex,
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.codex: 'gpt-global',
        AiAssistAgent.claude: 'sonnet',
        AiAssistAgent.opencode: 'provider/reading-model',
      },
      promptSettingsByOperation: <AiAssistOperation, AiAssistPromptSettings>{
        AiAssistOperation.commitMessage: AiAssistPromptSettings(
          agent: AiAssistAgent.claude,
        ),
        AiAssistOperation.pullRequestDetails: AiAssistPromptSettings(
          model: 'gpt-pull-request',
        ),
        AiAssistOperation.readingDiff: AiAssistPromptSettings(
          agent: AiAssistAgent.opencode,
        ),
      },
    );

    expect(
      settings.agentFor(AiAssistOperation.commitMessage),
      AiAssistAgent.claude,
    );
    expect(
      settings.modelForOperation(AiAssistOperation.commitMessage),
      'sonnet',
    );
    expect(
      settings.agentFor(AiAssistOperation.pullRequestDetails),
      AiAssistAgent.codex,
    );
    expect(
      settings.modelForOperation(AiAssistOperation.pullRequestDetails),
      'gpt-pull-request',
    );
    expect(
      settings.agentFor(AiAssistOperation.readingDiff),
      AiAssistAgent.opencode,
    );
    expect(
      settings.modelForOperation(AiAssistOperation.readingDiff),
      'provider/reading-model',
    );
    expect(
      settings.modelForOperation(AiAssistOperation.workspaceIdentity),
      'gpt-global',
    );
  });

  test('keeps operation reasoning overrides isolated with global fallback', () {
    const settings = AiAssistSettings(
      selectedThinkingByModel: <String, String>{'gpt-5.5': 'low'},
      selectedThinkingByOperation: <AiAssistOperation, Map<String, String>>{
        AiAssistOperation.commitMessage: <String, String>{'gpt-5.5': 'high'},
      },
    );

    expect(
      settings.thinkingForOperation(AiAssistOperation.commitMessage, 'gpt-5.5'),
      'high',
    );
    expect(
      settings.thinkingForOperation(
        AiAssistOperation.pullRequestDetails,
        'gpt-5.5',
      ),
      'low',
    );
  });

  test('reports whether prompt settings inherit each global value', () {
    const inherited = AiAssistPromptSettings(model: '  ');
    const overridden = AiAssistPromptSettings(
      agent: AiAssistAgent.claude,
      model: 'sonnet',
    );

    expect(inherited.inheritsAgent, isTrue);
    expect(inherited.inheritsModel, isTrue);
    expect(overridden.inheritsAgent, isFalse);
    expect(overridden.inheritsModel, isFalse);
  });
}
