import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_tab_hover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_tab_surface.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_transfer_row.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_transfer_scope.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/gestures.dart';
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

AgentChatSummary _summary(String id, String title, {String? forkedFrom}) =>
    AgentChatSummary.fromJson(<String, Object?>{
      'chatId': id,
      'workspaceId': 'ws-1',
      'title': title,
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'model': 'gpt-5',
      'status': 'ready',
      'updatedAt': '2026-10-12T10:00:00Z',
      'forkedFromChatId': ?forkedFrom,
    });

Map<String, Object?> _transfer(
  String id,
  String kind,
  String source, {
  String status = 'consumed',
  String? itemId,
  String? sourceTurnId,
}) => <String, Object?>{
  'transferId': id,
  'kind': kind,
  'sourceChatId': source,
  'targetChatId': 'chat-1',
  'status': status,
  'createdAt': '2026-10-12T10:00:10Z',
  'itemId': ?itemId,
  'sourceTurnId': ?sourceTurnId,
};

final List<AgentChatSummary> _chats = <AgentChatSummary>[
  _summary('chat-1', 'Fix the build', forkedFrom: 'origin'),
  _summary('origin', 'Plan the build'),
  _summary('fork-2', 'Cache experiment', forkedFrom: 'chat-1'),
];

/// One mouse per test, so a second hover moves it instead of adding another.
final Expando<TestGesture> _mice = Expando<TestGesture>();

Future<void> _hover(WidgetTester tester, Finder target) async {
  var mouse = _mice[tester];
  if (mouse == null) {
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    _mice[tester] = mouse;
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
  }
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _pumpSurface(WidgetTester tester) async {
  final repository = FakeAgentChatRepository()
    ..summaries = _chats
    ..snapshots.add(
      () =>
          agentChatSnapshotFixture(
            items: <Map<String, Object?>>[
              agentChatItemFixture('u1', 'user_message', text: 'Plan it'),
              agentChatItemFixture(
                'call',
                'collab_agent_tool_call',
                normalized: <String, Object?>{
                  'subagent': <String, Object?>{
                    'status': 'completed',
                    'description': 'Count files',
                    'model': 'gpt-6-luna',
                    'summary': 'Counted 42 files.',
                  },
                },
              ),
              agentChatItemFixture('a1', 'assistant_message', text: 'Planned'),
              agentChatItemFixture(
                'merged',
                'notice',
                turnId: null,
                text: '> User: Try an LRU cache',
                normalized: <String, Object?>{
                  'mergeBack': <String, Object?>{'status': 'pending'},
                },
              ),
            ],
          ).copyWith(
            contextTransfers: agentChatTransfersFromJson(<Object?>[
              _transfer('fork', 'fork', 'origin', sourceTurnId: 'turn-1'),
              _transfer(
                'merge',
                'mergeBack',
                'fork-2',
                status: 'pending',
                itemId: 'merged',
              ),
            ]),
          ),
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
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
}

void main() {
  testWidgets('transfers draw as timeline rows and lineage rows', (
    tester,
  ) async {
    await _pumpSurface(tester);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-transfer-fork')),
      findsOneWidget,
    );
    expect(find.text('Forked From'), findsOneWidget);
    expect(find.text('Merged Back From'), findsOneWidget);
    expect(find.text('· Waiting for Next Message'), findsOneWidget);
    // The merge-back notice folds under its row instead of a plain notice.
    expect(find.textContaining('Try an LRU cache'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-transfer-toggle-merge')),
    );
    await tester.pump();
    expect(
      find.textContaining('Try an LRU cache', findRichText: true),
      findsWidgets,
    );

    await _hover(tester, find.text('Sub-agent: Count files'));
    final subagentCard = find.byKey(
      const ValueKey<String>('agent-chat-preview-card'),
    );
    expect(
      find.descendant(
        of: subagentCard,
        matching: find.text('Counted 42 files.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: subagentCard, matching: find.text('gpt-6-luna')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('agent-chat-lineage')));
    await tester.pumpAndSettle();
    expect(find.text('Context Transfers'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-lineage-transfer-merge')),
      findsOneWidget,
    );
    expect(find.text('Merged Back From · Waiting for Next Message'), findsOne);
    expect(find.text('Forked From · Delivered'), findsOne);

    await _hover(
      tester,
      find.byKey(
        const ValueKey<String>('agent-chat-lineage-chat-origin-forkSource'),
      ),
    );
    final card = find.byKey(const ValueKey<String>('agent-chat-preview-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('gpt-5 · Codex')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Idle')),
      findsOneWidget,
    );
  });

  testWidgets('a transfer row opens its source and previews it on hover', (
    tester,
  ) async {
    final opened = <String>[];
    final transfer = AgentChatContextTransfer.tryParse(
      _transfer('result', 'subagentResult', 'origin'),
    )!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatRelatedChatsProvider.overrideWith((ref) async => _chats),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: AgentChatTransferScope(
              onOpenChat: opened.add,
              child: AgentChatTransferRowView(
                entry: AgentChatTransferEntry(transfer),
                expansion: AgentChatExpansion(),
                actions: AgentChatTimelineActions(
                  chatId: 'chat-1',
                  onRetrySend: (_) {},
                  onEditSend: (_) {},
                  onOpenLink: (_) {},
                  onOpenFile: (_) {},
                  onImplementPlan: () {},
                ),
                workspacePath: '/projects/alera',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Result From'), findsOneWidget);
    final link = find.byKey(
      const ValueKey<String>('agent-chat-transfer-source-result'),
    );
    expect(
      find.descendant(of: link, matching: find.text('Plan the build')),
      findsOne,
    );
    await _hover(tester, link);
    final card = find.byKey(const ValueKey<String>('agent-chat-preview-card'));
    expect(
      find.descendant(of: card, matching: find.text('Result From · Delivered')),
      findsOneWidget,
    );
    await tester.tap(link);
    expect(opened, <String>['origin']);
  });

  testWidgets('a chat tab previews its agent and where it came from', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatRelatedChatsProvider.overrideWith((ref) async => _chats),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(
            body: Center(
              child: AgentChatTabHover(chatId: 'chat-1', child: Text('Tab')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _hover(tester, find.text('Tab'));
    final card = find.byKey(const ValueKey<String>('agent-chat-preview-card'));
    expect(
      find.descendant(of: card, matching: find.text('Fix the build')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Forked from Plan the build'),
      ),
      findsOneWidget,
    );
  });
}
