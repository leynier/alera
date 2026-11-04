import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const String _id = '26ff2908-0cbd-4c5b-ad34-a8900ee80204';

/// Serves [_png] for `agentChat.attachment.read` when [supported].
final class _AttachmentTransport implements AgentChatTransport {
  _AttachmentTransport({this.supported = true, this.fails = false});

  final bool supported;
  final bool fails;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async =>
      supported && capability == AgentChatWire.attachmentReadCapability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    expect(type, AgentChatWire.attachmentRead);
    requests.add(payload);
    if (fails) throw StateError('relay offline');
    final bytes = base64Decode(_png);
    return <String, Object?>{
      'attachmentId': payload['attachmentId'],
      'mimeType': 'image/png',
      'sizeBytes': bytes.length,
      'offset': 0,
      'nextOffset': bytes.length,
      'dataBase64': _png,
    };
  }
}

AgentChatAttachment _attachment({String? attachmentId = _id}) =>
    AgentChatAttachment.fromJson(<String, Object?>{
      'type': 'localImage',
      'path': '/host/agent-chat-attachments/$_id.data.png',
      'name': 'photo.png',
      'sizeBytes': 70,
      'attachmentId': ?attachmentId,
    });

Future<void> _pump(
  WidgetTester tester,
  _AttachmentTransport transport,
  AgentChatAttachment attachment,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider('host-1')
            .overrideWith((ref) async => RuntimeAgentChatRepository(transport)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AgentChatScope(
            hostId: 'host-1',
            workspaceId: 'ws-1',
            chatId: 'chat-1',
            cwd: '/work',
            memory: AgentChatViewMemory(),
            child: AgentChatMessageAttachmentsView(
              attachments: <AgentChatAttachment>[attachment],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var index = 0; index < 4; index += 1) {
    await tester.pump();
  }
}

final Finder _hostImage = find.byKey(
  const ValueKey<String>('agent-chat-host-image-$_id'),
);

void main() {
  testWidgets('an image the phone did not pick loads from the host', (
    tester,
  ) async {
    final transport = _AttachmentTransport();
    await _pump(tester, transport, _attachment());
    expect(_hostImage, findsOneWidget);
    expect(transport.requests.single['chatId'], 'chat-1');
    expect(transport.requests.single['workspaceId'], 'ws-1');
    expect(transport.requests.single['attachmentId'], _id);
  });

  testWidgets('a host without the capability keeps the placeholder', (
    tester,
  ) async {
    final transport = _AttachmentTransport(supported: false);
    await _pump(tester, transport, _attachment());
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(transport.requests, isEmpty);
  });

  testWidgets('a failed read keeps the placeholder', (tester) async {
    final transport = _AttachmentTransport(fails: true);
    await _pump(tester, transport, _attachment());
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(transport.requests, hasLength(1));
  });

  testWidgets('an attachment without an upload id is never read', (
    tester,
  ) async {
    final transport = _AttachmentTransport();
    await _pump(tester, transport, _attachment(attachmentId: null));
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(transport.requests, isEmpty);
  });
}
