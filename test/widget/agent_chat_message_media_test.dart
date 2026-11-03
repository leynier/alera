import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
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

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> items, {
  bool running = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        status: running ? 'running' : 'ready',
        activeTurnId: running ? 'turn-1' : null,
        items: items,
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
}

Map<String, Object?> _message(
  String id,
  String text, {
  List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
}) => <String, Object?>{
  ...agentChatItemFixture(id, 'user_message', text: text),
  'attachments': attachments,
};

void main() {
  testWidgets('media sits above the bubble and files become cards', (
    tester,
  ) async {
    await _pump(tester, <Map<String, Object?>>[
      _message(
        'u1',
        'Look at these',
        attachments: <Map<String, Object?>>[
          <String, Object?>{'type': 'image', 'path': '/tmp/a.png'},
          <String, Object?>{'type': 'image', 'path': '/tmp/b.png'},
          <String, Object?>{
            'type': 'image',
            'path': '/tmp/Screenshot 2026-10-12.png',
          },
          <String, Object?>{
            'type': 'file',
            'path': '/tmp/report.pdf',
            'sizeBytes': 1258291,
          },
          <String, Object?>{
            'type': 'file',
            'path': '/tmp/pasted.txt',
            'name': 'Pasted File',
            'mimeType': 'text/plain',
            'sizeBytes': 2048,
          },
        ],
      ),
    ]);
    for (var index = 0; index < 3; index += 1) {
      expect(
        find.byKey(ValueKey<String>('agent-chat-media-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('agent-chat-media-3')),
      findsNothing,
    );
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('PDF · 1.2 MB'), findsOneWidget);
    expect(find.text('Pasted text'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    final bubble = find.byKey(
      const ValueKey<String>('agent-chat-user-message-u1'),
    );
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('agent-chat-media-0')),
          )
          .dy,
      lessThan(tester.getTopLeft(bubble).dy),
    );
  });

  testWidgets('files sent without text show only their cards', (tester) async {
    await _pump(tester, <Map<String, Object?>>[
      _message(
        'u1',
        '',
        attachments: <Map<String, Object?>>[
          <String, Object?>{'type': 'file', 'path': '/tmp/notes.md'},
        ],
      ),
    ]);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-file-card-0')),
      findsOneWidget,
    );
    expect(find.text('MD'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-user-message-u1')),
      findsNothing,
    );
  });

  testWidgets('back-to-back steers share one label', (tester) async {
    await _pump(tester, running: true, <Map<String, Object?>>[
      _message('u1', 'Fix the build'),
      agentChatItemFixture('a1', 'assistant_message', text: 'On it.'),
      _message('u2', 'Also run the tests'),
      _message('u3', 'And the linter'),
    ]);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-steer-u2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-steer-u3')),
      findsOneWidget,
    );
    expect(find.text('Sent during the turn'), findsOneWidget);
    final label = tester.getTopLeft(find.text('Sent during the turn')).dy;
    expect(
      label,
      greaterThan(
        tester
            .getBottomLeft(
              find.byKey(const ValueKey<String>('agent-chat-user-message-u3')),
            )
            .dy,
      ),
    );
  });
}
