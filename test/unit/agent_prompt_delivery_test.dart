import 'package:alera/src/features/agent_profiles/domain/agent_prompt_delivery.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent prompt delivery', () {
    test('every agent declares how its prompt reaches the launch', () {
      expect(
        <AgentType, AgentPromptDelivery>{
          for (final adapter in AgentType.values)
            adapter: agentPromptDeliveryFor(adapter),
        },
        <AgentType, AgentPromptDelivery>{
          AgentType.codex: AgentPromptDelivery.positionalAfterTerminator,
          AgentType.claude: AgentPromptDelivery.positionalAfterTerminator,
          AgentType.copilot: AgentPromptDelivery.longOption,
          AgentType.cursor: AgentPromptDelivery.positionalAfterTerminator,
          AgentType.agy: AgentPromptDelivery.longOption,
          AgentType.opencode: AgentPromptDelivery.longOption,
          AgentType.opencode2: AgentPromptDelivery.longOption,
          AgentType.pi: AgentPromptDelivery.positional,
          AgentType.amp: AgentPromptDelivery.stdinScript,
          // Hook-only, with no spawn adapter, so the default is what it gets.
          AgentType.grok: AgentPromptDelivery.positionalAfterTerminator,
        },
      );
    });

    test('describes every delivery path in the user\'s terms', () {
      expect(
        agentPromptDeliveryDescription(AgentType.codex),
        contains('after --'),
      );
      expect(
        agentPromptDeliveryDescription(AgentType.pi),
        contains('does not accept an option terminator'),
      );
      expect(
        agentPromptDeliveryDescription(AgentType.opencode),
        contains('--prompt'),
      );
      expect(
        agentPromptDeliveryDescription(AgentType.amp),
        contains('standard input'),
      );
    });

    test('previews the launch line in the shape each agent accepts', () {
      expect(
        agentPromptDeliveryPreview(AgentType.codex, '  codex --search  '),
        "codex --search -- 'Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(AgentType.claude, 'claude --model opus'),
        "claude --model opus -- 'Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(AgentType.copilot, 'copilot'),
        "copilot '--interactive=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(AgentType.opencode, 'opencode'),
        "opencode '--prompt=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(AgentType.agy, 'agy'),
        "agy '--prompt-interactive=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(AgentType.pi, 'pi --thinking high'),
        "pi --thinking high 'Dispatched Prompt'",
      );
      expect(agentPromptDeliveryPreview(AgentType.codex, '   '), '');
      // Amp's prompt never reaches the command line.
      expect(agentPromptDeliveryPreview(AgentType.amp, 'amp'), '');
    });
  });
}
