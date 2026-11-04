import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_tab_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
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

final WorkspaceTabRecord _tab = WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: 'ws-1',
  title: 'Fix the build',
  kind: WorkspaceTabKind.agentChat,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  payload: const <String, Object?>{'chatId': 'chat-1', 'provider': 'codex'},
);

final class _Lifecycle extends AgentChatLifecycleRepository {
  final calls = <(String, String)>[];
  final Set<String> capabilities = <String>{
    AgentChatWire.subagentThreadsCapability,
    AgentChatWire.mergeBackCapability,
  };

  @override
  Future<bool> supports(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<AgentChatSubagentTranscript> subagent(
    AgentChatRef chat, {
    required String itemId,
  }) async {
    calls.add(('subagent', itemId));
    return AgentChatSubagentTranscript(
      call: AgentChatItem.fromJson(_call()),
      items: <AgentChatItem>[
        AgentChatItem.fromJson(
          agentChatItemFixture(
            'older',
            'assistant_message',
            text: 'Older sub-agent note',
            normalized: <String, Object?>{'parentItemId': 'call'},
          ),
        ),
      ],
    );
  }

  @override
  Future<void> stopSubagent(
    AgentChatRef chat, {
    required String requestId,
    required String itemId,
  }) async => calls.add(('stop', itemId));

  @override
  Future<String> mergeBack(
    AgentChatRef chat, {
    required String requestId,
  }) async {
    calls.add(('mergeBack', chat.chatId));
    return 'origin';
  }
}

Map<String, Object?> _call() => agentChatItemFixture(
  'call',
  'collab_agent_tool_call',
  status: 'inProgress',
  normalized: <String, Object?>{
    'input': <String, Object?>{'prompt': 'Count every file in lib'},
    'subagent': <String, Object?>{
      'status': 'running',
      'description': 'Count files',
      'taskId': 'child-thread',
      'model': 'gpt-6-luna',
      'reasoningEffort': 'high',
      'startedAt': '2026-10-12T10:00:00Z',
    },
  },
);

AgentChatSummary _summary(String id, {String? forkedFrom, String? title}) =>
    AgentChatSummary.fromJson(<String, Object?>{
      'chatId': id,
      'workspaceId': 'ws-1',
      'title': title ?? 'Chat $id',
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'ready',
      'updatedAt': '2026-10-12T10:00:00Z',
      'forkedFromChatId': ?forkedFrom,
    });

Future<_Lifecycle> _pump(WidgetTester tester) async {
  final lifecycle = _Lifecycle();
  final repository = FakeAgentChatRepository()
    ..summaries = <AgentChatSummary>[
      _summary('chat-1', forkedFrom: 'origin', title: 'Fix the build'),
      _summary('origin', title: 'Plan the build'),
    ]
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        capabilities: const <String, Object?>{
          'interrupt': true,
          'stopSubagent': true,
        },
        items: <Map<String, Object?>>[
          agentChatItemFixture('u1', 'user_message', text: 'Count files'),
          _call(),
          agentChatItemFixture(
            'child',
            'assistant_message',
            text: 'Live sub-agent note',
            normalized: <String, Object?>{'parentItemId': 'call'},
          ),
          agentChatItemFixture('a1', 'assistant_message', text: 'Main answer'),
        ],
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
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatTabSurface(workspace: _workspace, tab: _tab),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return lifecycle;
}

void main() {
  testWidgets('a sub-agent opens in place of the chat, read-only', (
    tester,
  ) async {
    final lifecycle = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
    );
    await tester.pump();
    await tester.pump();
    expect(lifecycle.calls.first, ('subagent', 'call'));
    expect(find.text('Count every file in lib'), findsOneWidget);
    expect(find.text('Live sub-agent note', findRichText: true), findsOne);
    expect(find.text('Older sub-agent note', findRichText: true), findsOne);
    expect(find.text('Main answer', findRichText: true), findsNothing);
    // The sub-agent bar replaces the composer.
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-bar')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('agent-chat-send')), findsNothing);
    expect(find.text('gpt-6-luna'), findsOneWidget);
    expect(find.text('Runs on its own'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-status')),
      findsOne,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-stop')),
    );
    await tester.pump();
    expect(lifecycle.calls.last, ('stop', 'call'));

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-parent')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-bar')),
      findsNothing,
    );
    expect(find.text('Main answer', findRichText: true), findsOne);
  });

  testWidgets('the lineage control lists the fork source and merges back', (
    tester,
  ) async {
    final lifecycle = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('agent-chat-lineage')));
    await tester.pumpAndSettle();
    expect(find.text('Lineage · 1 running'), findsWidgets);
    expect(find.text('Plan the build'), findsOneWidget);
    expect(find.text('Forked From · Idle'), findsOneWidget);
    expect(find.text('Sub-agent · Running'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-lineage-merge')),
    );
    await tester.pump();
    expect(lifecycle.calls.last, ('mergeBack', 'chat-1'));
    await tester.pumpAndSettle();
  });

  testWidgets('an older runtime keeps sub-agents inline', (tester) async {
    final lifecycle = _Lifecycle()..capabilities.clear();
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(items: <Map<String, Object?>>[_call()]),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatComposerDraftsProvider.overrideWithValue(
            AgentChatComposerDrafts(),
          ),
          agentChatRepositoryProvider.overrideWithValue(repository),
          agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: AgentChatTabSurface(workspace: _workspace, tab: _tab),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-subagent-stop-call')),
      findsNothing,
    );
  });
}
