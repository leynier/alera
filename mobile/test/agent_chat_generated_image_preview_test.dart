import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_generated_image_preview.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

final class _ImageTransport implements AgentChatTransport {
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async => true;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add(payload);
    final bytes = base64Decode(_png);
    return <String, Object?>{
      'itemId': payload['itemId'],
      'mimeType': 'image/png',
      'sizeBytes': bytes.length,
      'offset': 0,
      'nextOffset': bytes.length,
      'contentToken': 'v1',
      'dataBase64': _png,
    };
  }
}

AgentChatItem _item(String status) => AgentChatItem.fromJson(<String, Object?>{
  'itemId': 'image-1',
  'turnId': 'turn-1',
  'type': 'image_generation',
  'status': status,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'normalized': <String, Object?>{'imagePath': '/codex/fox.png'},
});

void main() {
  testWidgets('a generated image shows under its row', (tester) async {
    final transport = _ImageTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatRepositoryProvider(
            'host-1',
          ).overrideWith((ref) async => RuntimeAgentChatRepository(transport)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AgentChatScope(
              hostId: 'host-1',
              workspaceId: 'ws-1',
              chatId: 'chat-1',
              cwd: '/work',
              memory: AgentChatViewMemory(),
              child: AgentChatGeneratedImagePreview(item: _item('completed')),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-generated-image-image-1')),
      findsOneWidget,
    );
    expect(transport.requests.single['itemId'], 'image-1');
    expect(agentChatShowsGeneratedImage(_item('completed')), isTrue);
    expect(agentChatShowsGeneratedImage(_item('inProgress')), isFalse);
  });
}
