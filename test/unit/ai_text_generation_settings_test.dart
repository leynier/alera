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
        'Workspace Identity',
      ],
    );
    expect(AiTextGenerationAgent.codex.agentType, AgentType.codex);
    expect(AiTextGenerationAgent.claude.agentType, AgentType.claude);
    expect(AiTextGenerationAgent.copilot.agentType, AgentType.copilot);
    expect(AiTextGenerationAgent.cursor.agentType, AgentType.cursor);
    expect(AiTextGenerationAgent.agy.agentType, AgentType.agy);
    expect(AiTextGenerationAgent.opencode.agentType, AgentType.opencode);
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
    );

    expect(AiTextGenerationSettings.fromJson(settings.toMap()), settings);
  });
}
