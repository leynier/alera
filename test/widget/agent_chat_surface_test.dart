import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';

import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
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

List<Map<String, Object?>> _completedTurn() => <Map<String, Object?>>[
  agentChatItemFixture('u1', 'user_message', text: 'Fix the build'),
  agentChatItemFixture(
    'c1',
    'command_execution',
    normalized: <String, Object?>{'command': 'make test', 'exitCode': 0},
  ),
  agentChatItemFixture(
    'f1',
    'file_change',
    normalized: <String, Object?>{
      'changes': <Object?>[
        <String, Object?>{
          'path': 'lib/main.dart',
          'kind': 'update',
          'diff': '+fixed\n-broken',
        },
      ],
    },
  ),
  agentChatItemFixture('a1', 'assistant_message', text: 'The build passes.'),
];

void main() {
  testWidgets('an older runtime asks for an update', (tester) async {
    await _pumpSurface(tester, FakeAgentChatRepository(isSupported: false));
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('agent-chat-send')), findsNothing);
  });

  testWidgets('a new chat names its agent and workspace', (tester) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture());
    await _pumpSurface(tester, repository);
    expect(find.byKey(const ValueKey<String>('agent-chat-empty')), findsOne);
    expect(find.text('Fix the build'), findsOneWidget);
    expect(find.text('/projects/alera'), findsOneWidget);
  });

  testWidgets('finished work folds under its duration', (tester) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          items: _completedTurn(),
          turns: <Map<String, Object?>>[
            <String, Object?>{
              'turnId': 'turn-1',
              'status': 'completed',
              'startedAt': '2026-10-12T10:00:00Z',
              'completedAt': '2026-10-12T10:00:42Z',
            },
          ],
        ),
      );
    await _pumpSurface(tester, repository);
    expect(find.text('Fix the build', findRichText: true), findsOneWidget);
    expect(find.text('The build passes.', findRichText: true), findsOneWidget);
    expect(find.text('Worked for 42s'), findsOneWidget);
    expect(find.text('Ran make test'), findsNothing);
    await tester.tap(find.text('Worked for 42s'));
    await tester.pump();
    expect(find.text('Edited 1 file, ran 1 command'), findsOneWidget);
    await tester.tap(find.text('Edited 1 file, ran 1 command'));
    await tester.pump();
    expect(find.text('Ran make test'), findsOneWidget);
    expect(find.text('Edited main.dart +1 -1'), findsOneWidget);
  });

  testWidgets('sending clears the composer and shows the message', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture(items: _completedTurn()))
      ..sendGate = Completer<void>();
    await _pumpSurface(tester, repository);
    await tester.enterText(find.byType(TextField).last, 'Now add tests');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Now add tests'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, isEmpty);
    final send = repository.calls.singleWhere((call) => call.$1 == 'send');
    expect((send.$2! as AgentChatSendInput).text, 'Now add tests');
    repository.sendGate!.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('a dropped connection keeps the chat readable', (tester) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture(items: _completedTurn()));
    await _pumpSurface(tester, repository);
    repository.events.add(const AgentChatConnectionLost());
    // The event lands after the first frame; the second one shows it.
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-reconnecting')),
      findsOneWidget,
    );
    expect(find.text('The build passes.', findRichText: true), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.enabled, isFalse);
  });

  testWidgets(
    'editing a failed send preserves the next draft and attachments',
    (tester) async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture())
        ..sendError = const AgentChatConnectionException('Connection lost.');
      await _pumpSurface(tester, repository);
      final composer = tester
          .widget<AgentChatComposer>(find.byType(AgentChatComposer))
          .controller;
      composer.addAttachment(
        kind: TerminalComposerAttachmentKind.file,
        path: '/projects/alera/shared.txt',
        displayName: 'shared.txt',
      );
      await tester.enterText(find.byType(TextField).last, 'Retry this message');
      await tester.tap(find.byKey(const ValueKey<String>('agent-chat-send')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Edit'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'My next draft');
      composer.addAttachment(
        kind: TerminalComposerAttachmentKind.file,
        path: '/projects/alera/shared.txt',
        displayName: 'shared.txt',
      );
      composer.addAttachment(
        kind: TerminalComposerAttachmentKind.file,
        path: '/projects/alera/next.txt',
        displayName: 'next.txt',
      );
      await tester.pump();
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(
        composer.textController.text,
        'My next draft\n\nRetry this message',
      );
      expect(
        composer.textController.selection,
        TextSelection.collapsed(offset: composer.textController.text.length),
      );
      expect(
        composer.attachments.map((attachment) => attachment.path),
        <String>['/projects/alera/shared.txt', '/projects/alera/next.txt'],
      );
      expect(find.text('Edit'), findsNothing);
      repository.sendError = null;
      await tester.tap(find.byKey(const ValueKey<String>('agent-chat-send')));
      await tester.pump();
      final input =
          repository.calls.lastWhere((call) => call.$1 == 'send').$2!
              as AgentChatSendInput;
      expect(input.text, 'My next draft\n\nRetry this message');
      expect(input.attachments, hasLength(2));
    },
  );

  testWidgets('an approval is answered from the request dock', (tester) async {
    final repository = FakeAgentChatRepository()
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
            },
          ],
        ),
      );
    await _pumpSurface(tester, repository);
    expect(find.text('rm -rf build', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Allow Once'));
    await tester.pump();
    final respond = repository.calls.singleWhere(
      (call) => call.$1 == 'respond',
    );
    final (requestId, response) = respond.$2! as (String, AgentChatResponse);
    expect(requestId, 'r1');
    expect(
      (response as AgentChatApprovalResponse).decision,
      AgentChatApprovalDecision.accept,
    );
  });

  testWidgets('editing an attachment-only failure leaves draft text intact', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture())
      ..sendError = const AgentChatConnectionException('Connection lost.');
    await _pumpSurface(tester, repository);
    final composer = tester
        .widget<AgentChatComposer>(find.byType(AgentChatComposer))
        .controller;
    composer.addAttachment(
      kind: TerminalComposerAttachmentKind.file,
      path: '/projects/alera/context.txt',
      displayName: 'context.txt',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('agent-chat-send')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).last,
      'Explain the attachment',
    );
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(composer.textController.text, 'Explain the attachment');
    expect(composer.attachments.single.path, '/projects/alera/context.txt');
    expect(
      composer.textController.selection,
      const TextSelection.collapsed(offset: 22),
    );
  });

  testWidgets('automated input reads as a notice, not as the person', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          items: <Map<String, Object?>>[
            agentChatItemFixture(
              'u1',
              'user_message',
              text: 'Two delegated tasks finished.',
              normalized: <String, Object?>{
                'origin': <String, Object?>{
                  'kind': 'orchestrationWake',
                  'taskIds': <Object?>['t1', 't2'],
                },
              },
            ),
          ],
        ),
      );
    await _pumpSurface(tester, repository);
    expect(
      find.text('Resumed after 2 delegated tasks finished'),
      findsOneWidget,
    );
    expect(
      find.text('Two delegated tasks finished.', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('a sub-agent wake reads as a runtime notice', (tester) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          items: <Map<String, Object?>>[
            agentChatItemFixture(
              'u1',
              'user_message',
              text: 'Subagent completed: Count the files',
              normalized: <String, Object?>{
                'origin': <String, Object?>{
                  'kind': 'subagentWake',
                  'taskIds': <Object?>['child'],
                },
              },
            ),
          ],
        ),
      );
    await _pumpSurface(tester, repository);
    expect(find.text('Resumed after a sub-agent finished'), findsOneWidget);
    expect(
      find.text('Subagent completed: Count the files', findRichText: true),
      findsNothing,
    );
  });
}
