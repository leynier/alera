import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentStatusController completion states', () {
    late List<DateTime> times;
    late ProviderContainer container;

    setUp(() {
      times = <DateTime>[
        DateTime.utc(2026, 5, 26, 1),
        DateTime.utc(2026, 5, 26, 1, 1),
        DateTime.utc(2026, 5, 26, 1, 2),
        DateTime.utc(2026, 5, 26, 1, 3),
        DateTime.utc(2026, 5, 26, 1, 4),
      ];
      var index = 0;
      container = ProviderContainer(
        overrides: [
          agentStatusClockProvider.overrideWithValue(() => times[index++]),
        ],
      );
      addTearDown(container.dispose);
    });

    test('normalizes Amp prompt, tool, assistant, and cancelled states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.amp,
          hookEventName: 'agent.start',
          payload: <String, Object?>{'message': 'update docs'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.amp,
          hookEventName: 'tool.call',
          payload: <String, Object?>{
            'tool': 'bash',
            'input': <String, Object?>{'command': 'dart format .'},
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.amp,
          hookEventName: 'agent.end',
          payload: <String, Object?>{
            'status': 'cancelled',
            'messages': <Object?>[
              <String, Object?>{
                'role': 'assistant',
                'content': <Object?>[
                  <String, Object?>{'type': 'text', 'text': 'All set.'},
                ],
              },
            ],
          },
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.prompt, 'update docs');
      expect(entry.toolName, 'bash');
      expect(entry.toolInput, 'dart format .');
      expect(entry.lastAssistantMessage, 'All set.');
      expect(entry.interrupted, isTrue);
    });

    test('marks active terminal exits as inferred done', () {
      final controller = container.read(agentStatusControllerProvider.notifier);
      controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'run tests'},
        ),
      );

      controller.markTerminalExited(
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        exitCode: 0,
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.lastAssistantMessage, 'Terminal exited with code 0.');
      expect(entry.stateStartedAt, times[1]);
    });
  });
}

AgentHookEvent _event({
  required AgentType agentType,
  required String hookEventName,
  required Map<String, Object?> payload,
}) {
  return AgentHookEvent(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: agentType,
    hookEventName: hookEventName,
    payload: payload,
  );
}
