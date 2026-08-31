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
          AgentType.grok: AgentPromptDelivery.positionalAfterTerminator,
          AgentType.fx: AgentPromptDelivery.terminalAfterReady,
        },
      );
    });

    test('describes every delivery path in the user\'s terms', () {
      expect(agentPromptDeliveryDescription(.codex), contains('after --'));
      expect(
        agentPromptDeliveryDescription(.pi),
        contains('does not accept an option terminator'),
      );
      expect(agentPromptDeliveryDescription(.opencode), contains('--prompt'));
      expect(agentPromptDeliveryDescription(.amp), contains('standard input'));
      expect(
        agentPromptDeliveryDescription(.fx),
        contains('report that its interactive interface is ready'),
      );
    });

    test('previews the launch line in the shape each agent accepts', () {
      expect(
        agentPromptDeliveryPreview(.codex, '  codex --search  '),
        "codex --search -- 'Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.claude, 'claude --model opus'),
        "claude --model opus -- 'Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.grok, 'grok --effort high'),
        "grok --effort high -- 'Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.copilot, 'copilot'),
        "copilot '--interactive=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.opencode, 'opencode'),
        "opencode '--prompt=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.agy, 'agy'),
        "agy '--prompt-interactive=Dispatched Prompt'",
      );
      expect(
        agentPromptDeliveryPreview(.pi, 'pi --thinking high'),
        "pi --thinking high 'Dispatched Prompt'",
      );
      expect(agentPromptDeliveryPreview(.codex, '   '), '');
      // Amp's prompt never reaches the command line.
      expect(agentPromptDeliveryPreview(.amp, 'amp'), '');
      expect(agentPromptDeliveryPreview(.fx, 'fx'), '');
    });
  });
}
