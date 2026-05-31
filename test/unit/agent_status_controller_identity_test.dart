import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentStatusController identity inheritance', () {
    test('keeps active parent identity for inherited working events', () {
      final harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'implement feature'},
        ),
      );
      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'Bash',
            'tool_input': <String, Object?>{'command': 'flutter test'},
          },
        ),
      );

      final entry = harness.entry;
      expect(entry.agentType, AgentType.codex);
      expect(entry.state, AgentStatusState.working);
      expect(entry.prompt, 'implement feature');
      expect(entry.toolName, 'Bash');
      expect(entry.toolInput, 'flutter test');
    });

    test('keeps active parent identity for inherited blocked events', () {
      final harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'ship release'},
        ),
      );
      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.copilot,
          hookEventName: 'Notification',
          payload: <String, Object?>{
            'notificationType': 'elicitation_dialog',
            'message': 'Which environment?',
          },
        ),
      );

      final entry = harness.entry;
      expect(entry.agentType, AgentType.codex);
      expect(entry.state, AgentStatusState.blocked);
      expect(entry.prompt, 'ship release');
      expect(entry.lastAssistantMessage, 'Which environment?');
    });

    test('ignores inherited done events from a nested child agent', () {
      final harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'parent task'},
        ),
      );
      final before = harness.entry;

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'Stop',
          payload: <String, Object?>{
            'last_assistant_message': 'Nested child finished.',
          },
        ),
      );

      final after = harness.entry;
      expect(after.agentType, AgentType.codex);
      expect(after.state, AgentStatusState.working);
      expect(after.lastAssistantMessage, isNull);
      expect(after.updatedAt, before.updatedAt);
    });

    test('ignores inherited close events from nested child agents', () {
      final harness = _Harness(
        times: <DateTime>[
          DateTime.utc(2026, 5, 26, 1),
          DateTime.utc(2026, 5, 26, 1, 1),
          DateTime.utc(2026, 5, 26, 1, 2),
          DateTime.utc(2026, 5, 26, 1, 3),
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'parent task'},
        ),
      );

      for (final close in const <({AgentType agentType, String eventName})>[
        (agentType: AgentType.copilot, eventName: 'SessionEnd'),
        (agentType: AgentType.cursor, eventName: 'sessionEnd'),
        (agentType: AgentType.pi, eventName: 'session_shutdown'),
      ]) {
        harness.controller.applyHookEvent(
          _event(
            agentType: close.agentType,
            hookEventName: close.eventName,
            payload: <String, Object?>{},
          ),
        );
        expect(harness.entry.agentType, AgentType.codex);
        expect(harness.entry.state, AgentStatusState.working);
      }
    });

    test('allows a new child identity after the parent is done', () {
      final harness = _Harness();
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'parent task'},
        ),
      );
      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'Stop',
          payload: <String, Object?>{'last_assistant_message': 'Done.'},
        ),
      );
      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'Edit',
            'tool_input': <String, Object?>{'file_path': 'lib/main.dart'},
          },
        ),
      );

      final entry = harness.entry;
      expect(entry.agentType, AgentType.claude);
      expect(entry.state, AgentStatusState.working);
      expect(entry.toolName, 'Edit');
      expect(entry.toolInput, 'lib/main.dart');
    });

    test('allows a new child identity after the parent status is stale', () {
      final harness = _Harness(
        times: <DateTime>[
          DateTime.utc(2026, 5, 26, 1),
          DateTime.utc(2026, 5, 26, 1, 31, 1),
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{'prompt': 'parent task'},
        ),
      );
      harness.controller.applyHookEvent(
        _event(
          agentType: AgentType.claude,
          hookEventName: 'PreToolUse',
          payload: <String, Object?>{
            'tool_name': 'Bash',
            'tool_input': <String, Object?>{'command': 'dart test'},
          },
        ),
      );

      final entry = harness.entry;
      expect(entry.agentType, AgentType.claude);
      expect(entry.state, AgentStatusState.working);
      expect(entry.toolName, 'Bash');
      expect(entry.toolInput, 'dart test');
    });
  });
}

class _Harness {
  _Harness({List<DateTime>? times})
    : _times =
          times ??
          <DateTime>[
            DateTime.utc(2026, 5, 26, 1),
            DateTime.utc(2026, 5, 26, 1, 1),
            DateTime.utc(2026, 5, 26, 1, 2),
            DateTime.utc(2026, 5, 26, 1, 3),
          ] {
    var index = 0;
    container = ProviderContainer(
      overrides: [
        agentStatusClockProvider.overrideWithValue(() => _times[index++]),
      ],
    );
  }

  final List<DateTime> _times;
  late final ProviderContainer container;

  AgentStatusController get controller =>
      container.read(agentStatusControllerProvider.notifier);

  AgentStatusEntry get entry =>
      container.read(agentStatusControllerProvider)['session-1']!;

  void dispose() {
    container.dispose();
  }
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
