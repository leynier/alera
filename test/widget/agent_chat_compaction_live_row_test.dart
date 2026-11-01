import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(String id, String type, String status) =>
    <String, Object?>{
      'itemId': id,
      'turnId': 'turn-1',
      'type': type,
      'status': status,
      'createdAt': '2026-10-12T10:00:00Z',
      'updatedAt': '2026-10-12T10:00:00Z',
      'text': '',
      'normalized': type == 'command_execution'
          ? <String, Object?>{'command': 'step $id'}
          : const <String, Object?>{},
    };

AgentChatTurnSection _section(String compaction) =>
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{
            'status': 'running',
            'activeTurnId': 'turn-1',
          },
          'turns': <Object?>[],
          'items': <Object?>[
            _item('c1', 'command_execution', 'completed'),
            _item('k1', 'context_compaction', compaction),
          ],
        }),
      ),
    ).entries.whereType<AgentChatTurnEntry>().single.section;

void _ignore(String _) {}

void _noop() {}

void main() {
  testWidgets('a running compaction times itself in the live row', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 12, 10, 0, 12);
    Future<void> pump(AgentChatTurnSection section) => tester.pumpWidget(
      ProviderScope(
        overrides: [agentChatClockProvider.overrideWithValue(() => now)],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentChatTurnView(
                section: section,
                actions: const AgentChatTimelineActions(
                  chatId: 'chat-1',
                  onRetrySend: _ignore,
                  onEditSend: _ignore,
                  onOpenLink: _ignore,
                  onOpenFile: _ignore,
                  onImplementPlan: _noop,
                ),
                expansion: AgentChatExpansion(),
                workspacePath: '/work',
              ),
            ),
          ),
        ),
      ),
    );
    await pump(_section('inProgress'));
    expect(find.text('Compacting for 12s'), findsOneWidget);
    expect(find.byIcon(AleraIcons.contextCompact), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Compacting for 13s'), findsOneWidget);
    expect(find.textContaining('Working for'), findsOneWidget);

    await pump(_section('completed'));
    expect(find.textContaining('Compacting for'), findsNothing);
  });
}
