import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 10, 26, 12);

String _label(String provider) => provider == 'codex' ? 'Codex' : provider;

AgentChatSummary _chat({
  String status = 'ready',
  int pending = 0,
  bool archived = false,
}) => AgentChatSummary.fromJson(<String, Object?>{
  'chatId': 'source',
  'workspaceId': 'ws',
  'title': 'Cache experiment',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'model': 'gpt-5',
  'status': status,
  'pendingRequestCount': pending,
  'archived': archived,
  'updatedAt': _now.subtract(const Duration(minutes: 5)).toIso8601String(),
});

List<String> _texts(AgentChatPreview preview) => <String>[
  for (final line in preview.lines) line.text,
];

void main() {
  test('a chat preview names its relation, agent, state and activity', () {
    final preview = AgentChatPreview.chat(
      _chat(pending: 1),
      fallbackTitle: 'Fork',
      relation: 'Fork',
      providerLabel: _label,
      now: _now,
    );
    expect(preview.title, 'Cache experiment');
    expect(_texts(preview), <String>[
      'Fork',
      'gpt-5 · Codex',
      'Needs Input',
      'Updated 5 min ago',
    ]);
    expect(preview.lines[1].provider, 'codex');
    expect(preview.lines[2].tone, AgentChatPreviewTone.working);
  });

  test('a chat this device cannot see keeps its fallback title', () {
    final preview = AgentChatPreview.chat(null, fallbackTitle: 'Parent Chat');
    expect(preview.title, 'Parent Chat');
    expect(_texts(preview), <String>['Unavailable on this device']);
  });

  test('a sub-agent preview shows model, effort, timing and summary', () {
    final call = AgentChatItem.fromJson(<String, Object?>{
      'itemId': 'call',
      'turnId': 't',
      'type': 'collab_agent_tool_call',
      'status': 'completed',
      'createdAt': _now.toIso8601String(),
      'normalized': <String, Object?>{
        'subagent': <String, Object?>{
          'status': 'completed',
          'description': 'Survey the cache',
          'model': 'gpt-5-mini',
          'reasoningEffort': 'high',
          'summary': '\nLRU wins by 40%.\nDetails follow.',
          'startedAt': _now.toIso8601String(),
          'completedAt': _now
              .add(const Duration(seconds: 42))
              .toIso8601String(),
        },
      },
    });
    final preview = AgentChatPreview.subagent(
      call,
      provider: 'codex',
      providerLabel: _label,
      now: _now,
    );
    expect(preview.title, 'Survey the cache');
    expect(_texts(preview), <String>[
      'gpt-5-mini · Codex · high',
      'Completed in 42s',
      'LRU wins by 40%.',
    ]);
    expect(preview.lines[1].tone, AgentChatPreviewTone.success);
  });

  test('a transfer preview reads its kind, status and delivery', () {
    final transfer = AgentChatContextTransfer.tryParse(<String, Object?>{
      'transferId': 't',
      'kind': 'mergeBack',
      'sourceChatId': 'source',
      'targetChatId': 'chat',
      'status': 'pending',
      'createdAt': _now.subtract(const Duration(hours: 2)).toIso8601String(),
    })!;
    final pending = AgentChatPreview.transfer(
      transfer,
      sourceTitle: 'Cache experiment',
      source: _chat(),
      providerLabel: _label,
      now: _now,
    );
    expect(_texts(pending), <String>[
      'Merged Back From · Waiting for Next Message',
      'gpt-5 · Codex',
      'Sent 2 h ago',
    ]);
    expect(pending.lines.first.tone, AgentChatPreviewTone.working);
    final missing = AgentChatPreview.transfer(
      transfer,
      sourceTitle: 'Cache experiment',
      now: _now,
    );
    expect(_texts(missing).last, 'Source chat unavailable');
  });
}
