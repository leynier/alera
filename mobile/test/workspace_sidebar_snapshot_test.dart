import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('View prefs preserve the pinned workspace display option', () {
    final hidden = MobileViewPrefs.fromJson(<String, Object?>{
      'showPinnedWorkspacesBelow': false,
    });
    final legacy = MobileViewPrefs.fromJson(const <String, Object?>{});

    expect(hidden.showPinnedWorkspacesBelow, isFalse);
    expect(hidden.toJson()['showPinnedWorkspacesBelow'], isFalse);
    expect(legacy.showPinnedWorkspacesBelow, isTrue);
  });

  test('View prefs preserve the active workspace filter', () {
    final activeOnly = MobileViewPrefs.fromJson(<String, Object?>{
      'showActiveWorkspacesOnly': true,
    });
    final legacy = MobileViewPrefs.fromJson(const <String, Object?>{});

    expect(activeOnly.showActiveWorkspacesOnly, isTrue);
    expect(activeOnly.toJson()['showActiveWorkspacesOnly'], isTrue);
    expect(legacy.showActiveWorkspacesOnly, isFalse);
  });

  test('View prefs preserve the archived workspace filter', () {
    final shown = MobileViewPrefs.fromJson(<String, Object?>{
      'showArchivedWorkspaces': true,
    });
    final legacy = MobileViewPrefs.fromJson(const <String, Object?>{});

    expect(shown.showArchivedWorkspaces, isTrue);
    expect(shown.toJson()['showArchivedWorkspaces'], isTrue);
    expect(legacy.showArchivedWorkspaces, isFalse);
  });

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
          'title': 'Map Monetization',
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
    expect(status.title, 'Map Monetization');
  });

  test('Parses agent presence without a title from an older host', () {
    final snapshot = WorkspaceSidebarSnapshot.fromJson(<String, Object?>{
      'projects': <Object?>[],
      'workspaces': <Object?>[],
      'tags': <Object?>[],
      'activity': <String, Object?>{},
      'viewPrefs': <String, Object?>{},
      'runtimeSettings': <String, Object?>{},
      'agentPresence': <Object?>[
        <String, Object?>{
          'handle': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'agentType': 'codex',
          'agentState': 'waiting',
        },
      ],
    });

    expect(snapshot.agentPresence.single.title, isEmpty);
  });

  test('Parses main-panel tab ids from an additive snapshot field', () {
    final snapshot = WorkspaceSidebarSnapshot.fromJson(<String, Object?>{
      'projects': <Object?>[],
      'workspaces': <Object?>[],
      'tags': <Object?>[],
      'activity': <String, Object?>{},
      'viewPrefs': <String, Object?>{},
      'runtimeSettings': <String, Object?>{},
      'workspaceMainTabIds': <String, Object?>{
        'workspace-1': <Object?>['tab-1', '', 2],
      },
    });

    expect(snapshot.workspaceMainTabIds, <String, List<String>>{
      'workspace-1': <String>['tab-1'],
    });
    expect(
      WorkspaceSidebarSnapshot.fromJson(<String, Object?>{
        'projects': <Object?>[],
        'workspaces': <Object?>[],
        'tags': <Object?>[],
        'activity': <String, Object?>{},
        'viewPrefs': <String, Object?>{},
        'runtimeSettings': <String, Object?>{},
      }).workspaceMainTabIds,
      isEmpty,
    );
  });
}
