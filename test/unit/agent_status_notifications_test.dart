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

    test('composes attention and done notifications only', () {
      final waiting = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.waiting, prompt: 'Review command'),
        includeFinished: true,
        projectName: 'Alera',
        workspaceName: 'main',
        tabTitle: 'Codex',
      );
      final blocked = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.blocked,
          agentType: AgentType.copilot,
          prompt: 'Choose target',
        ),
        includeFinished: true,
      );
      final done = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.done,
          agentType: AgentType.agy,
          prompt: '',
        ),
        includeFinished: true,
        projectName: 'Alera',
        workspaceName: 'main',
        tabTitle: 'Claude',
      );
      final cursorDone = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.done,
          agentType: AgentType.cursor,
          prompt: 'Ship Cursor',
        ),
        includeFinished: true,
      );
      final working = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.working),
        includeFinished: true,
      );
      final openCodeDone = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.done,
          agentType: AgentType.opencode,
          prompt: 'Finish plugin',
        ),
        includeFinished: true,
      );
      final piWaiting = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.waiting,
          agentType: AgentType.pi,
          prompt: 'Approve command',
        ),
        includeFinished: true,
      );
      final ampDone = composeAgentStatusNotification(
        entry: _entry(
          AgentStatusState.done,
          agentType: AgentType.amp,
          prompt: 'Ship plugin',
        ),
        includeFinished: true,
      );

      expect(waiting, isNotNull);
      expect(waiting!.title, 'Codex needs attention');
      expect(waiting.body, 'Workspace main in Alera');
      expect(waiting.body, isNot(contains('Review command')));
      expect(blocked, isNotNull);
      expect(blocked!.title, 'GitHub Copilot needs attention');
      expect(blocked.body, 'Open Alera');
      expect(done, isNotNull);
      expect(done!.title, 'Antigravity finished');
      expect(done.body, 'Workspace main in Alera');
      expect(cursorDone!.title, 'Cursor finished');
      expect(openCodeDone!.title, 'OpenCode finished');
      expect(piWaiting!.title, 'Pi needs attention');
      expect(ampDone!.title, 'Amp finished');
      expect(working, isNull);
    });

    test('skips done notifications unless finished notifications are on', () {
      final done = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.done),
        includeFinished: false,
      );
      final waiting = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.waiting),
        includeFinished: false,
      );
      final blocked = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.blocked),
        includeFinished: false,
      );

      expect(done, isNull);
      expect(waiting!.title, 'Codex needs attention');
      expect(blocked!.title, 'Codex needs attention');
    });

    test('composes fallback notification titles and location bodies', () {
      final workspaceOnly = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.waiting),
        includeFinished: true,
        workspaceName: 'feature/login',
      );
      final tabOnly = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.done),
        includeFinished: true,
        tabTitle: 'Terminal 2',
      );

      expect(workspaceOnly!.body, 'Workspace feature/login');
      expect(tabOnly!.title, 'Codex finished');
      expect(tabOnly.body, 'Terminal Terminal 2');
    });

    test('drops the project when it repeats the workspace name', () {
      final sameName = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.waiting),
        includeFinished: true,
        projectName: 'alera',
        workspaceName: 'alera',
      );
      final sameNameDifferentCase = composeAgentStatusNotification(
        entry: _entry(AgentStatusState.done),
        includeFinished: true,
        projectName: 'Alera',
        workspaceName: ' alera ',
      );

      expect(sameName!.body, 'Workspace alera');
      expect(sameNameDifferentCase!.body, 'Workspace alera');
    });
  });
}

AgentStatusEntry _entry(
  AgentStatusState state, {
  String prompt = 'Run tests',
  AgentType agentType = AgentType.codex,
  String sessionId = 'session-1',
  DateTime? updatedAt,
  DateTime? stateStartedAt,
}) {
  return AgentStatusEntry(
    terminalSessionId: sessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: agentType,
    state: state,
    prompt: prompt,
    updatedAt: updatedAt ?? DateTime.utc(2026, 5, 26, 12),
    stateStartedAt: stateStartedAt ?? DateTime.utc(2026, 5, 26, 12),
  );
}
