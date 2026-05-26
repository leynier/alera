import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentStatusController', () {
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

    test('normalizes Codex events and preserves state start time', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'make a plan'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'Bash',
            'tool_input': <String, Object?>{'command': 'flutter analyze'},
          },
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.working);
      expect(entry.prompt, 'make a plan');
      expect(entry.toolName, 'Bash');
      expect(entry.toolInput, 'flutter analyze');
      expect(entry.updatedAt, times[1]);
      expect(entry.stateStartedAt, times[0]);
    });

    test('normalizes waiting, done, and Claude interrupt states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'PermissionRequest',
          payload: <String, Object?>{
            'prompt': 'edit files',
            'tool_name': 'Edit',
            'tool_input': <String, Object?>{'file_path': 'lib/main.dart'},
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'Stop',
          payload: <String, Object?>{
            'is_interrupt': true,
            'last_assistant_message': 'Cancelled by user.',
          },
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.interrupted, isTrue);
      expect(entry.lastAssistantMessage, 'Cancelled by user.');
      expect(entry.stateStartedAt, times[1]);
    });

    test('normalizes Copilot blocked and done states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.copilot,
          hookEventName: 'userPromptSubmitted',
          payload: <String, Object?>{'prompt': 'deploy the app'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.copilot,
          hookEventName: 'Notification',
          payload: <String, Object?>{
            'notificationType': 'elicitation_dialog',
            'message': 'Which environment?',
          },
        ),
      );

      var entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.blocked);
      expect(entry.prompt, 'deploy the app');
      expect(entry.lastAssistantMessage, 'Which environment?');

      controller.applyHookEvent(
        _event(
          agentType: AgentType.copilot,
          hookEventName: 'SessionEnd',
          payload: <String, Object?>{'lastAssistantMessage': 'Done.'},
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.lastAssistantMessage, 'Done.');
    });

    test('normalizes AGY invocation and feedback tool states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.agy,
          hookEventName: 'PreInvocation',
          payload: <String, Object?>{'prompt': 'fix test'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.agy,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'toolCall': <String, Object?>{
              'name': 'ask_question',
              'args': <String, Object?>{'Prompt': 'Which file?'},
            },
          },
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.prompt, 'fix test');
      expect(entry.toolName, 'ask_question');
      expect(entry.toolInput, 'Which file?');
    });

    test('normalizes OpenCode message, waiting, and idle states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.opencode,
          hookEventName: 'MessagePart',
          payload: <String, Object?>{'role': 'user', 'text': 'ship status'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.opencode,
          hookEventName: 'MessagePart',
          payload: <String, Object?>{
            'role': 'assistant',
            'text': 'Working on it.',
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.opencode,
          hookEventName: 'AskUserQuestion',
          payload: <String, Object?>{},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.opencode,
          hookEventName: 'SessionIdle',
          payload: <String, Object?>{},
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.prompt, 'ship status');
      expect(entry.lastAssistantMessage, 'Working on it.');
      expect(entry.stateStartedAt, times[3]);
    });

    test('normalizes Pi prompt, tool, assistant, and done states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: AgentType.pi,
          hookEventName: 'before_agent_start',
          payload: <String, Object?>{'prompt': 'rename helper'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.pi,
          hookEventName: 'tool_call',
          payload: <String, Object?>{
            'tool_name': 'bash',
            'tool_input': <String, Object?>{'command': 'flutter test'},
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.pi,
          hookEventName: 'message_end',
          payload: <String, Object?>{'role': 'assistant', 'text': 'Done.'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: AgentType.pi,
          hookEventName: 'agent_end',
          payload: <String, Object?>{},
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.prompt, 'rename helper');
      expect(entry.toolName, 'bash');
      expect(entry.toolInput, 'flutter test');
      expect(entry.lastAssistantMessage, 'Done.');
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
