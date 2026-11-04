import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Serves the one-pixel image as the runtime does.
final class _ImageTransport implements AgentChatTransport {
  final List<String> requests = <String>[];

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
    requests.add(type);
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

AgentChatTurnSection _section(String status) =>
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{'status': 'idle'},
          'turns': <Object?>[
            <String, Object?>{'turnId': 'turn-1', 'status': 'completed'},
          ],
          'items': <Object?>[
            <String, Object?>{
              'itemId': 'image-1',
              'turnId': 'turn-1',
              'type': 'image_generation',
              'status': status,
              'title': 'Generated image',
              'createdAt': '2026-10-12T10:00:00Z',
              'updatedAt': '2026-10-12T10:00:00Z',
              'normalized': <String, Object?>{'imagePath': '/codex/fox.png'},
            },
            <String, Object?>{
              'itemId': 'answer',
              'turnId': 'turn-1',
              'type': 'assistant_message',
              'status': 'completed',
              'text': 'Here it is.',
              'createdAt': '2026-10-12T10:00:01Z',
              'updatedAt': '2026-10-12T10:00:01Z',
            },
          ],
        }),
      ),
    ).entries.whereType<AgentChatTurnEntry>().single.section;

void _ignore(String _) {}

void _noop() {}

void main() {
  testWidgets('a generated image shows under its row and opens its file', (
    tester,
  ) async {
    final transport = _ImageTransport();
    final opened = <String>[];
    final expansion = AgentChatExpansion()
      ..set(agentChatTurnFoldKey('turn-1'), expanded: true);
    Future<void> pump(String status) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatLifecycleRepositoryProvider.overrideWithValue(
            RuntimeAgentChatLifecycleRepository(transport),
          ),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentChatTurnView(
                section: _section(status),
                actions: AgentChatTimelineActions(
                  chatId: 'chat-1',
                  workspaceId: 'ws-1',
                  onRetrySend: _ignore,
                  onEditSend: _ignore,
                  onOpenLink: _ignore,
                  onOpenFile: opened.add,
                  onImplementPlan: _noop,
                ),
                expansion: expansion,
                workspacePath: '/work',
              ),
            ),
          ),
        ),
      ),
    );
    await pump('completed');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final preview = find.byKey(
      const ValueKey<String>('agent-chat-generated-image-image-1'),
    );
    expect(preview, findsOneWidget);
    // The pixel decodes off the test clock, so the tap goes to the handler.
    tester.widget<GestureDetector>(preview).onTap!();
    expect(opened, <String>['/codex/fox.png']);
    expect(transport.requests, <String>[AgentChatWire.generatedImage]);
    await pump('inProgress');
    await tester.pump();
    expect(preview, findsNothing);
  });
}
