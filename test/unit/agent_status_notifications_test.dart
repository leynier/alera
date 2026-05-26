import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent status notifications', () {
    test('encodes and decodes activation payloads', () {
      final payload = const AgentStatusNotificationPayload(
        terminalSessionId: 'session-1',
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        agentType: AgentType.codex,
        state: AgentStatusState.done,
      ).encode();

      final decoded = decodeAgentStatusNotificationPayload(payload);

      expect(decoded, isNotNull);
      expect(decoded!.terminalSessionId, 'session-1');
      expect(decoded.workspaceId, 'workspace-1');
      expect(decoded.tabId, 'tab-1');
      expect(decoded.agentType, AgentType.codex);
      expect(decoded.state, AgentStatusState.done);
    });

    test('rejects malformed or incomplete activation payloads', () {
      expect(decodeAgentStatusNotificationPayload(null), isNull);
      expect(decodeAgentStatusNotificationPayload(''), isNull);
      expect(decodeAgentStatusNotificationPayload('not json'), isNull);
      expect(
        decodeAgentStatusNotificationPayload('{"workspaceId":"workspace-1"}'),
        isNull,
      );
    });

    test('composes waiting and done notifications only', () {
      final waiting = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.waiting, prompt: 'Review command'),
        workspaceName: 'Alera',
        tabTitle: 'Codex',
      );
      final done = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.done, prompt: ''),
        workspaceName: 'Alera',
        tabTitle: 'Claude',
      );
      final working = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.working),
      );

      expect(waiting, isNotNull);
      expect(waiting!.title, 'Codex needs attention');
      expect(waiting.body, 'Review command');
      expect(done, isNotNull);
      expect(done!.title, 'Codex finished');
      expect(done.body, 'Claude');
      expect(working, isNull);
    });

    test('deduplicates unchanged states by terminal and state start time', () {
      final tracker = AgentStatusNotificationTracker();
      final firstWaiting = _entry(AgentStatusState.waiting);
      final sameWaiting = firstWaiting.copyWith(
        updatedAt: DateTime.utc(2026, 5, 26, 12, 1),
      );
      final nextWaiting = firstWaiting.copyWith(
        stateStartedAt: DateTime.utc(2026, 5, 26, 12, 2),
        updatedAt: DateTime.utc(2026, 5, 26, 12, 2),
      );

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{
            firstWaiting.terminalSessionId: firstWaiting,
          },
        ),
        <AgentStatusEntry>[firstWaiting],
      );
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{
            firstWaiting.terminalSessionId: firstWaiting,
          },
          next: <String, AgentStatusEntry>{
            sameWaiting.terminalSessionId: sameWaiting,
          },
        ),
        isEmpty,
      );
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{
            sameWaiting.terminalSessionId: sameWaiting,
          },
          next: <String, AgentStatusEntry>{
            nextWaiting.terminalSessionId: nextWaiting,
          },
        ),
        <AgentStatusEntry>[nextWaiting],
      );
    });
  });
}

AgentStatusEntry _entry(AgentStatusState state, {String prompt = 'Run tests'}) {
  return AgentStatusEntry(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    state: state,
    prompt: prompt,
    updatedAt: DateTime.utc(2026, 5, 26, 12),
    stateStartedAt: DateTime.utc(2026, 5, 26, 12),
  );
}
