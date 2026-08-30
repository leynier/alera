import 'package:alera/src/features/agent_status/application/agent_hook_lifecycle_guard.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentHookLifecycleGuard', () {
    test('bounds completed Amp threads and clears workspace state', () {
      final guard = AgentHookLifecycleGuard();

      expect(
        guard.shouldApply(_ampEvent('session.start', threadId: 'thread-0')),
        isFalse,
      );
      expect(
        guard.shouldApply(_ampEvent('agent.start', threadId: 'thread-0')),
        isTrue,
      );
      for (var index = 0; index < 33; index++) {
        expect(
          guard.shouldApply(_ampEvent('agent.end', threadId: 'thread-$index')),
          isTrue,
        );
      }

      expect(
        guard.shouldApply(_ampEvent('tool.result', threadId: 'thread-0')),
        isTrue,
      );
      expect(
        guard.shouldApply(_ampEvent('tool.result', threadId: 'thread-32')),
        isFalse,
      );

      guard.clearWorkspace('workspace-1');

      expect(
        guard.shouldApply(_ampEvent('tool.result', threadId: 'thread-32')),
        isTrue,
      );
    });

    test('supports legacy Amp payloads without a thread id', () {
      final guard = AgentHookLifecycleGuard();

      expect(guard.shouldApply(_ampEvent('agent.start')), isTrue);
      expect(guard.shouldApply(_ampEvent('agent.end')), isTrue);
      expect(guard.shouldApply(_ampEvent('tool.call')), isFalse);

      guard.clearTerminal('session-1');

      expect(guard.shouldApply(_ampEvent('tool.call')), isTrue);
    });
  });
}

AgentHookEvent _ampEvent(String eventName, {String? threadId}) {
  return AgentHookEvent(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: .amp,
    hookEventName: eventName,
    payload: <String, Object?>{'threadId': ?threadId},
  );
}
