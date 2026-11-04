import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_approval_focus.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/projects/alera',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

const Key _row = ValueKey<String>('agent-chat-approval-row-r1');
const Key _dock = ValueKey<String>('agent-chat-request-dock');

Future<FakeAgentChatRepository> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
}) async {
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        status: 'waiting',
        activeTurnId: 'turn-1',
        items: <Map<String, Object?>>[
          agentChatItemFixture('u1', 'user_message', text: 'Clean up'),
        ],
        requests: requests,
      ),
    );
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatSurface(
            chatId: 'chat-1',
            workspace: _workspace,
            fallbackTitle: 'Agent Chat',
            fallbackProvider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repository;
}

Map<String, Object?> _approval() => <String, Object?>{
  'requestId': 'r1',
  'kind': 'command_execution_approval',
  'turnId': 'turn-1',
  'createdAt': '2026-10-12T10:00:00Z',
  'command': 'rm -rf build',
  'cwd': '/projects/alera',
  'decisions': <Object?>['accept', 'decline'],
};

void main() {
  testWidgets('a pending approval waits on its timeline row, not the dock', (
    tester,
  ) async {
    await _pump(tester, requests: <Map<String, Object?>>[_approval()]);
    final row = find.byKey(_row);
    expect(row, findsOneWidget);
    expect(find.byKey(_dock), findsNothing);
    // The rows take the keyboard as the dock did.
    expect(
      find.ancestor(of: row, matching: find.byType(AgentChatApprovalFocus)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('rm -rf build')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('in /projects/alera')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Waiting for approval')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('agent-chat-timeline')),
        matching: row,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a decision on the row answers the approval', (tester) async {
    final repository = await _pump(
      tester,
      requests: <Map<String, Object?>>[_approval()],
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(_row),
        matching: find.byKey(
          const ValueKey<String>('agent-chat-decision-accept'),
        ),
      ),
    );
    await tester.pump();
    final (requestId, response) =
        repository.calls.singleWhere((call) => call.$1 == 'respond').$2!
            as (String, AgentChatResponse);
    expect(requestId, 'r1');
    expect(response.toJson(), <String, Object?>{
      'type': 'approval',
      'decision': 'accept',
    });
  });

  testWidgets('a question stays in the dock beside the approval row', (
    tester,
  ) async {
    await _pump(
      tester,
      requests: <Map<String, Object?>>[
        _approval(),
        <String, Object?>{
          'requestId': 'q1',
          'kind': 'tool_user_input',
          'turnId': 'turn-1',
          'createdAt': '2026-10-12T10:00:01Z',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'scope',
              'question': 'Which folder?',
              'options': <Object?>[
                <String, Object?>{'label': 'build'},
              ],
            },
          ],
        },
      ],
    );
    expect(find.byKey(_row), findsOneWidget);
    expect(find.byKey(_dock), findsOneWidget);
    expect(find.text('Which folder?'), findsOneWidget);
    expect(find.text('Request 1 of 2'), findsNothing);
  });
}
