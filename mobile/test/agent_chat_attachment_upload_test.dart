import 'dart:async';
import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

/// The paired workspace client of a runtime that takes chat uploads, with
/// its chat verbs answered by [chat].
class _UploadingWorkspaceClient extends FakeTerminalClient
    implements MobileAgentChatClient {
  _UploadingWorkspaceClient(this.chat);

  final FakeAgentChatClient chat;

  @override
  Set<String> get runtimeCapabilities => chat.runtimeCapabilities;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) => chat.requestMap(type, payload, timeout);
}

final class _FilePicker implements PromptFilePicker {
  @override
  Future<PromptFile?> pickFile() async =>
      PromptFile(name: 'notes.txt', sizeBytes: 4, openRead: _bytes);
}

// A generator rather than Stream.value: under the widget tester's fake async
// zone, cancelling Stream.value mid-event never completes, so a failed chunk
// would hang instead of reaching the picker's error path.
Stream<List<int>> _bytes() async* {
  yield <int>[1, 2, 3, 4];
}

/// Holds each chunk until the test releases it, so the composer can be
/// observed mid-upload.
final class _GatedChunks {
  final List<Completer<void>> gates = <Completer<void>>[];
  Object? failure;

  Future<Map<String, Object?>> chunk(Map<String, Object?> payload) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    if (failure case final failure?) throw failure;
    final data = payload['dataBase64']! as String;
    return <String, Object?>{
      'nextOffset': (payload['offset']! as int) + base64Decode(data).length,
    };
  }
}

Future<(FakeAgentChatClient, _GatedChunks)> _pumpChat(
  WidgetTester tester,
) async {
  final client = FakeAgentChatClient(
    capabilities: <String>{
      'agentChatV1',
      AgentChatWire.attachmentUploadCapability,
    },
  );
  final chunks = _GatedChunks();
  client.handlers['agentChat.snapshot'] = (_) =>
      agentChatSnapshot(session: agentChatSession(attachments: true));
  client.handlers[AgentChatWire.attachmentStart] = (payload) =>
      <String, Object?>{
        'uploadId': payload['uploadId'],
        'chunkBytes': 2,
        'offset': 0,
        'complete': false,
      };
  client.handlers[AgentChatWire.attachmentChunk] = chunks.chunk;
  client.handlers[AgentChatWire.attachmentComplete] = (payload) =>
      <String, Object?>{
        'type': 'file',
        'path': '/runtime/uploads/notes.txt',
        'name': 'notes.txt',
        'sizeBytes': 4,
        'attachmentId': payload['uploadId'],
      };
  final workspace = _UploadingWorkspaceClient(client);
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        promptFilePickerProvider.overrideWithValue(_FilePicker()),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AgentChatTabView(
            hostId: 'host',
            workspaceId: 'workspace-1',
            chatId: 'chat-1',
            provider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (client, chunks);
}

Future<void> _pickFile(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add Attachment'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Files'));
  // The sheet animates away while the first chunk is held.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _releaseChunk(WidgetTester tester, _GatedChunks chunks) async {
  chunks.gates.last.complete();
  await tester.pump();
  await tester.pump();
}

IconButton _button(WidgetTester tester, String tooltip) => tester.widget(
  find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
);

void main() {
  testWidgets('an upload shows progress and holds Send until it lands', (
    tester,
  ) async {
    final (client, chunks) = await _pumpChat(tester);
    await tester.enterText(find.byType(TextField), 'Read this');
    await tester.pump();

    await _pickFile(tester);
    expect(chunks.gates, hasLength(1));
    expect(find.text('Uploading attachment'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(_button(tester, 'Send').onPressed, isNull);
    expect(_button(tester, 'Add Attachment').onPressed, isNull);

    await _releaseChunk(tester, chunks);
    expect(find.text('50%'), findsOneWidget);
    expect(_button(tester, 'Send').onPressed, isNull);

    await _releaseChunk(tester, chunks);
    await tester.pumpAndSettle();
    expect(find.text('Uploading attachment'), findsNothing);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('Read this'), findsOneWidget);
    expect(_button(tester, 'Send').onPressed, isNotNull);
    expect(client.payloadsOf(AgentChatWire.attachmentComplete), hasLength(1));
    expect(find.byType(AgentChatTabView), findsOneWidget);
  });

  testWidgets('a failed upload keeps the text and offers Retry', (
    tester,
  ) async {
    final (_, chunks) = await _pumpChat(tester);
    await tester.enterText(find.byType(TextField), 'Read this');
    await tester.pump();

    await _pickFile(tester);
    chunks.failure = const AgentChatConnectionException('Connection lost.');
    await _releaseChunk(tester, chunks);
    await tester.pumpAndSettle();
    expect(find.text('Uploading attachment'), findsNothing);
    expect(find.text('The attachment did not upload.'), findsOneWidget);
    expect(find.text('Read this'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(_button(tester, 'Send').onPressed, isNotNull);

    // Retry opens the picker again; nothing navigates away from the chat.
    chunks.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Files'), findsOneWidget);
    await tester.tap(find.text('Files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('The attachment did not upload.'), findsNothing);
    expect(find.text('Uploading attachment'), findsOneWidget);
    await _releaseChunk(tester, chunks);
    await _releaseChunk(tester, chunks);
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.byType(AgentChatTabView), findsOneWidget);
  });

  testWidgets('Dismiss clears a failed upload notice', (tester) async {
    final (_, chunks) = await _pumpChat(tester);
    await _pickFile(tester);
    chunks.failure = const AgentChatConnectionException('Connection lost.');
    await _releaseChunk(tester, chunks);
    await tester.pumpAndSettle();
    expect(find.text('The attachment did not upload.'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('The attachment did not upload.'), findsNothing);
  });
}
