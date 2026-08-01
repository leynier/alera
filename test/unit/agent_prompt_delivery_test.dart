import 'package:alera/src/features/agent_profiles/domain/agent_prompt_delivery.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent prompt delivery', () {
    test('only Codex receives its prompt as a command argument', () {
      expect(
        <AgentType, AgentPromptDelivery>{
          for (final adapter in AgentType.values)
            adapter: agentPromptDeliveryFor(adapter),
        },
        <AgentType, AgentPromptDelivery>{
          AgentType.codex: AgentPromptDelivery.initialPromptArgument,
          AgentType.claude: AgentPromptDelivery.readinessInjection,
          AgentType.copilot: AgentPromptDelivery.readinessInjection,
          AgentType.cursor: AgentPromptDelivery.readinessInjection,
          AgentType.agy: AgentPromptDelivery.readinessInjection,
          AgentType.opencode: AgentPromptDelivery.readinessInjection,
          AgentType.pi: AgentPromptDelivery.readinessInjection,
          AgentType.amp: AgentPromptDelivery.readinessInjection,
          AgentType.grok: AgentPromptDelivery.readinessInjection,
        },
      );
    });

    test('describes both delivery paths in the user\'s terms', () {
      expect(
        agentPromptDeliveryDescription(AgentType.codex),
        contains('Appends The Dispatched Prompt'),
      );
      expect(
        agentPromptDeliveryDescription(AgentType.claude),
        contains('Types The Dispatched Prompt'),
      );
    });

    test('previews the launch line only where the prompt is an argument', () {
      expect(
        agentPromptDeliveryPreview(AgentType.codex, '  codex --search  '),
        "codex --search -- 'Dispatched Prompt'",
      );
      expect(agentPromptDeliveryPreview(AgentType.codex, '   '), '');
      expect(agentPromptDeliveryPreview(AgentType.claude, 'claude'), '');
    });
  });
}
