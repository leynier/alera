import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_attachment_preparation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
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

/// Each send's upload waits on the next gate, so a test can hold it open.
final class _GatedUploads {
  final List<Completer<List<AgentChatAttachment>>> gates =
      <Completer<List<AgentChatAttachment>>>[];

  Future<List<AgentChatAttachment>> prepare(
    AgentChatRef chat,
    List<AgentChatAttachment> attachments,
    String clientMessageId,
  ) {
    final gate = Completer<List<AgentChatAttachment>>();
    gates.add(gate);
    return gate.future;
  }

  void finish(List<AgentChatAttachment> attachments) =>
      gates.last.complete(<AgentChatAttachment>[
        for (final attachment in attachments)
          AgentChatAttachment(
            type: attachment.type,
            path: '/runtime/uploads/${attachment.displayName}',
            name: attachment.displayName,
            attachmentId: 'upload-${attachment.displayName}',
            sizeBytes: 4,
          ),
      ]);
}

Future<void> _pumpSurface(
  WidgetTester tester,
  FakeAgentChatRepository repository,
  _GatedUploads uploads,
) async {
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatPrepareAttachmentsProvider.overrideWithValue(uploads.prepare),
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

Future<void> _sendLocalFile(WidgetTester tester, String text) async {
  tester
      .widget<AgentChatComposer>(find.byType(AgentChatComposer))
      .controller
      .addAttachment(
        kind: TerminalComposerAttachmentKind.file,
        path: '/home/me/notes.txt',
        displayName: 'notes.txt',
        localSourcePath: '/home/me/notes.txt',
      );
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey<String>('agent-chat-send')));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('an outgoing row names the upload instead of Sending', (
    tester,
  ) async {
    final message = AgentChatOutgoingMessage(
      clientMessageId: 'm1',
      text: 'Read this',
      createdAt: DateTime.utc(2026, 10, 12, 10),
    );
    Future<void> pumpRow({required bool uploading}) => tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatOutgoingMessageView(
            message: message,
            uploading: uploading,
            onRetry: () {},
            onEdit: () {},
          ),
        ),
      ),
    );

    await pumpRow(uploading: true);
    expect(find.text(agentChatUploadingFilesLabel), findsOneWidget);
    expect(find.text('Sending'), findsNothing);

    await pumpRow(uploading: false);
    expect(find.text(agentChatUploadingFilesLabel), findsNothing);
    expect(find.text('Sending'), findsOneWidget);
  });

  testWidgets('a send shows Uploading files, then Sending once uploaded', (
    tester,
  ) async {
    final uploads = _GatedUploads();
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture())
      ..sendGate = Completer<void>();
    await _pumpSurface(tester, repository, uploads);

    await _sendLocalFile(tester, 'Read this');
    expect(uploads.gates, hasLength(1));
    expect(find.text(agentChatUploadingFilesLabel), findsOneWidget);
    expect(find.text('Sending'), findsNothing);
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);

    uploads.finish(<AgentChatAttachment>[
      const AgentChatAttachment(
        type: AgentChatAttachmentType.file,
        path: '/home/me/notes.txt',
        name: 'notes.txt',
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text(agentChatUploadingFilesLabel), findsNothing);
    expect(find.text('Sending'), findsOneWidget);
    final send = repository.calls.singleWhere((call) => call.$1 == 'send');
    final input = send.$2! as AgentChatSendInput;
    expect(input.attachments.single.attachmentId, 'upload-notes.txt');

    repository.sendGate!.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('a failed upload keeps Retry and Edit, and Retry uploads again', (
    tester,
  ) async {
    final uploads = _GatedUploads();
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture());
    await _pumpSurface(tester, repository, uploads);

    await _sendLocalFile(tester, 'Read this');
    expect(find.text(agentChatUploadingFilesLabel), findsOneWidget);
    uploads.gates.last.completeError(
      const AgentChatConnectionException('Connection lost.'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(agentChatUploadingFilesLabel), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(uploads.gates, hasLength(2));
    expect(find.text(agentChatUploadingFilesLabel), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
