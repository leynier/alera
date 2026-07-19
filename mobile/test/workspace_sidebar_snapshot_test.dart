import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Parses runtime terminal counts and full agent details', () {
    final snapshot = WorkspaceSidebarSnapshot.fromJson(<String, Object?>{
      'projects': <Object?>[],
      'workspaces': <Object?>[],
      'tags': <Object?>[],
      'activity': <String, Object?>{},
      'viewPrefs': <String, Object?>{},
      'runtimeSettings': <String, Object?>{},
      'terminalTabCountByWorkspaceId': <String, Object?>{'workspace-1': 2},
      'agentPresence': <Object?>[
        <String, Object?>{
          'handle': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'agentType': 'codex',
          'agentState': 'waiting',
          'stateStartedAt': '2026-07-19T10:00:00Z',
          'updatedAt': '2026-07-19T10:01:00Z',
          'prompt': 'Choose a deployment',
          'toolName': 'request_user_input',
          'toolInput': '{"environment":"production"}',
          'lastAssistantMessage': 'Waiting for approval',
          'interrupted': false,
        },
      ],
    });

    expect(snapshot.terminalTabCountByWorkspaceId, <String, int>{
      'workspace-1': 2,
    });
    final status = snapshot.agentPresence.single;
    expect(status.workspaceId, 'workspace-1');
    expect(status.agentType, 'codex');
    expect(status.state, 'waiting');
    expect(status.prompt, 'Choose a deployment');
    expect(status.toolName, 'request_user_input');
    expect(status.lastAssistantMessage, 'Waiting for approval');
    expect(status.interrupted, isFalse);
  });
}
