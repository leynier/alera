import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent status notification grouping', () {
    test('keeps per-agent copy for a single location', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting),
            projectName: 'Alera',
            workspaceName: 'main',
          ),
        ],
        includeFinished: false,
      );

      expect(notification!.title, 'Codex needs attention');
      expect(notification.body, 'Workspace main in Alera');
    });

    test('collapses several locations into one notification', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(
              AgentStatusState.blocked,
              sessionId: 'session-2',
              agentType: AgentType.claude,
            ),
            workspaceName: 'feature/login',
          ),
        ],
        includeFinished: false,
      );

      expect(notification!.title, '2 agents need attention');
      expect(notification.body, 'main, feature/login');
    });

    test('names the mixed and finished groups apart', () {
      final finished = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.done, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.done, sessionId: 'session-2'),
            workspaceName: 'docs',
          ),
        ],
        includeFinished: true,
      );
      final mixed = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.done, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting, sessionId: 'session-2'),
            workspaceName: 'docs',
          ),
        ],
        includeFinished: true,
      );

      expect(finished!.title, '2 agents finished');
      expect(mixed!.title, '2 agent updates');
    });

    test('summarises the tail past three named locations', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          for (var index = 0; index < 5; index++)
            AgentStatusNotificationLocation(
              entry: _entry(
                AgentStatusState.waiting,
                sessionId: 'session-$index',
              ),
              workspaceName: 'workspace-$index',
            ),
        ],
        includeFinished: false,
      );

      expect(notification!.title, '5 agents need attention');
      expect(
        notification.body,
        'workspace-0, workspace-1, workspace-2 and 2 more',
      );
    });

    test('falls back to tab title and agent name when unnamed', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting, sessionId: 'session-1'),
            tabTitle: 'Terminal 1',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(
              AgentStatusState.waiting,
              sessionId: 'session-2',
              agentType: AgentType.claude,
            ),
          ),
        ],
        includeFinished: false,
      );

      expect(notification!.body, 'Terminal 1, Claude');
    });

    test('drops finished entries from a group when they are off', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.done, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting, sessionId: 'session-2'),
            workspaceName: 'docs',
          ),
        ],
        includeFinished: false,
      );
      final onlyFinished = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.done, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
        ],
        includeFinished: false,
      );

      expect(notification!.title, 'Codex needs attention');
      expect(notification.body, 'Workspace docs');
      expect(onlyFinished, isNull);
    });

    test('points the grouped payload at the terminal that moved last', () {
      final notification = composeAgentStatusNotifications(
        locations: <AgentStatusNotificationLocation>[
          AgentStatusNotificationLocation(
            entry: _entry(AgentStatusState.waiting, sessionId: 'session-1'),
            workspaceName: 'main',
          ),
          AgentStatusNotificationLocation(
            entry: _entry(
              AgentStatusState.waiting,
              sessionId: 'session-2',
              updatedAt: DateTime.utc(2026, 5, 26, 12, 5),
            ),
            workspaceName: 'docs',
          ),
        ],
        includeFinished: false,
      );

      final payload = decodeAgentStatusNotificationPayload(
        notification!.payload,
      );
      expect(payload!.terminalSessionId, 'session-2');
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
