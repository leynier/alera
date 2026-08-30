import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'grok_agent_status_controller_test_cases.dart';
part 'agy_agent_status_controller_test_cases.dart';
part 'agent_status_snapshot_test_cases.dart';
part 'agent_status_controller_test_harness.dart';

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
        DateTime.utc(2026, 5, 26, 1, 5),
        DateTime.utc(2026, 5, 26, 1, 6),
        DateTime.utc(2026, 5, 26, 1, 7),
        DateTime.utc(2026, 5, 26, 1, 8),
        DateTime.utc(2026, 5, 26, 1, 9),
        DateTime.utc(2026, 5, 26, 1, 10),
        DateTime.utc(2026, 5, 26, 1, 11),
      ];
      var index = 0;
      container = ProviderContainer(
        overrides: [
          agentStatusClockProvider.overrideWithValue(() => times[index++]),
        ],
      );
      addTearDown(container.dispose);
    });

    _registerGrokAgentStatusControllerTests(() => container);
    _registerAgyAgentStatusControllerTests(() => container);
    _registerAgentStatusSnapshotTests(() => container);

    test('normalizes Codex events and preserves state start time', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'make a plan'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .codex,
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
      expect(
        container.read(agentStatusByTerminalSessionProvider('session-1')),
        same(entry),
      );
      expect(
        container.read(agentStatusByTerminalSessionProvider('missing')),
        isNull,
      );
    });

    test('normalizes human input tool use as waiting', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'functions.request_user_input',
            'tool_input': <String, Object?>{'question': 'Approve command?'},
          },
        ),
      );

      var entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.toolName, 'functions.request_user_input');
      expect(entry.toolInput, 'Approve command?');

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'request_user_input',
            'tool_input': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{'question': 'Which path should I use?'},
              ],
            },
          },
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.toolName, 'request_user_input');
      expect(entry.toolInput, 'Which path should I use?');

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'toolCall': <String, Object?>{
              'name': 'request_user_input',
              'args': <String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{'question': 'Which implementation option?'},
                ],
              },
            },
          },
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.toolName, 'request_user_input');
      expect(entry.toolInput, 'Which implementation option?');

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'functions.request_approval',
            'tool_input': <String, Object?>{
              'command': 'flutter test',
              'reason': 'Run the focused suite.',
            },
          },
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.toolName, 'functions.request_approval');
      expect(entry.toolInput, 'flutter test');

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'request_permissions',
            'tool_input': <String, Object?>{
              'reason': 'Need workspace write access.',
            },
          },
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.toolName, 'request_permissions');
      expect(entry.toolInput, 'Need workspace write access.');

      controller.applyHookEvent(
        _event(
          agentType: .codex,
          hookEventName: 'PermissionRequest',
          payload: <String, Object?>{'tool_name': 'Bash'},
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);

      controller.applyHookEvent(
        _event(
          agentType: .claude,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'askUser',
            'tool_input': <String, Object?>{'question': 'Which target?'},
          },
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.waiting);
      expect(entry.agentType, AgentType.codex);
      expect(entry.toolName, 'askUser');
      expect(entry.toolInput, 'Which target?');
    });

    test('normalizes waiting, done, and Claude interrupt states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: .claude,
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
          agentType: .claude,
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
          agentType: .copilot,
          hookEventName: 'userPromptSubmitted',
          payload: <String, Object?>{'prompt': 'deploy the app'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .copilot,
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
          agentType: .copilot,
          hookEventName: 'Stop',
          payload: <String, Object?>{'lastAssistantMessage': 'Done.'},
        ),
      );

      entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.lastAssistantMessage, 'Done.');

      controller.applyHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: 'SessionEnd',
          payload: <String, Object?>{},
        ),
      );

      expect(
        container.read(agentStatusControllerProvider).containsKey('session-1'),
        isFalse,
      );
    });

    test('normalizes Cursor tool, waiting, done, and response states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'beforeSubmitPrompt',
          payload: <String, Object?>{'prompt': 'ship cursor'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'preToolUse',
          payload: <String, Object?>{
            'tool_name': 'Edit',
            'tool_input': <String, Object?>{'file_path': 'lib/main.dart'},
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'postToolUseFailure',
          payload: <String, Object?>{'error_message': 'Patch failed.'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'beforeMCPExecution',
          payload: <String, Object?>{'url': 'https://example.test/mcp'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'stop',
          payload: <String, Object?>{'status': 'interrupted'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'afterAgentResponse',
          payload: <String, Object?>{'text': 'Final response.'},
        ),
      );

      final entry = container.read(agentStatusControllerProvider)['session-1']!;
      expect(entry.state, AgentStatusState.done);
      expect(entry.prompt, 'ship cursor');
      expect(entry.toolName, 'MCP');
      expect(entry.toolInput, 'https://example.test/mcp');
      expect(entry.lastAssistantMessage, 'Final response.');
      expect(entry.interrupted, isTrue);
      expect(entry.stateStartedAt, times[4]);
    });

    test('normalizes OpenCode message, waiting, and idle states', () {
      final controller = container.read(agentStatusControllerProvider.notifier);

      controller.applyHookEvent(
        _event(
          agentType: .opencode,
          hookEventName: 'MessagePart',
          payload: <String, Object?>{'role': 'user', 'text': 'ship status'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .opencode,
          hookEventName: 'MessagePart',
          payload: <String, Object?>{
            'role': 'assistant',
            'text': 'Working on it.',
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .opencode,
          hookEventName: 'AskUserQuestion',
          payload: <String, Object?>{},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .opencode,
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
          agentType: .pi,
          hookEventName: 'before_agent_start',
          payload: <String, Object?>{'prompt': 'rename helper'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .pi,
          hookEventName: 'tool_call',
          payload: <String, Object?>{
            'tool_name': 'bash',
            'tool_input': <String, Object?>{'command': 'flutter test'},
          },
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .pi,
          hookEventName: 'message_end',
          payload: <String, Object?>{'role': 'assistant', 'text': 'Done.'},
        ),
      );
      controller.applyHookEvent(
        _event(
          agentType: .pi,
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

      controller.applyHookEvent(
        _event(
          agentType: .pi,
          hookEventName: 'session_shutdown',
          payload: <String, Object?>{},
        ),
      );

      expect(
        container.read(agentStatusControllerProvider).containsKey('session-1'),
        isFalse,
      );
    });
  });
}
