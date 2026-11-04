import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<void> _pumpSurface(
  WidgetTester tester,
  FakeAgentChatRepository repository,
) async {
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
}

FakeAgentChatRepository _waiting({bool feedback = false}) =>
    FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          status: 'waiting',
          activeTurnId: 'turn-1',
          items: <Map<String, Object?>>[
            agentChatItemFixture('u1', 'user_message', text: 'Clean up'),
          ],
          requests: <Map<String, Object?>>[
            <String, Object?>{
              'requestId': 'r1',
              'kind': 'command_execution_approval',
              'turnId': 'turn-1',
              'createdAt': '2026-10-12T10:00:00Z',
              'command': 'rm -rf build',
              'decisions': <Object?>['accept', 'decline'],
              'supportsFeedback': feedback,
            },
          ],
        ),
      );

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;

void main() {
  testWidgets('typing over a feedback approval declines it with the text', (
    tester,
  ) async {
    final repository = _waiting(feedback: true);
    await _pumpSurface(tester, repository);
    expect(find.text(agentChatApprovalFeedbackHint), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Keep the cache.');
    await tester.pump();
    expect(find.byTooltip(agentChatApprovalFeedbackSendLabel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    final (requestId, response) =
        repository.calls.singleWhere((call) => call.$1 == 'respond').$2!
            as (String, AgentChatResponse);
    expect(requestId, 'r1');
    expect(response.toJson(), <String, Object?>{
      'type': 'approval',
      'decision': 'decline',
      'feedback': 'Keep the cache.',
    });
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);
    expect(_composerText(tester), isEmpty);
  });

  testWidgets('a message over an approval declines it, then redirects', (
    tester,
  ) async {
    final repository = _waiting();
    await _pumpSurface(tester, repository);
    expect(find.text(agentChatApprovalRedirectHint), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Run tests instead.');
    await tester.pump();
    expect(find.byTooltip(agentChatApprovalRedirectSendLabel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    final names = <String>[
      for (final (name, _) in repository.calls)
        if (name == 'respond' || name == 'send') name,
    ];
    expect(names, <String>['respond', 'send']);
    final send =
        repository.calls.singleWhere((call) => call.$1 == 'send').$2!
            as AgentChatSendInput;
    expect(send.text, 'Run tests instead.');
    expect(_composerText(tester), isEmpty);
  });
}
