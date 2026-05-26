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
