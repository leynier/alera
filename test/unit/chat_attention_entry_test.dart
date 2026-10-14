import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_transitions.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _at = DateTime.utc(2026, 10, 13, 9);

ChatAttentionEntry _entry(
  String chatId, {
  String workspaceId = 'ws-1',
  AgentChatSessionStatus status = AgentChatSessionStatus.ready,
  bool pending = false,
  int children = 0,
  bool childNeedsInput = false,
  bool unread = false,
  DateTime? updatedAt,
}) => ChatAttentionEntry(
  chatId: chatId,
  workspaceId: workspaceId,
  title: 'Chat $chatId',
  tabId: 'tab-$chatId',
  updatedAt: updatedAt ?? _at,
  status: status,
  hasPendingRequests: pending,
  openChildTaskCount: children,
  childNeedsInput: childNeedsInput,
  unread: unread,
);

void main() {
  group('level', () {
    test('ranks needs input, failed, unread, working, waiting on tasks', () {
      expect(_entry('a', pending: true).level, ChatAttentionLevel.needsInput);
      expect(
        _entry('a', childNeedsInput: true).level,
        ChatAttentionLevel.needsInput,
      );
      expect(
        _entry('a', status: AgentChatSessionStatus.error, unread: true).level,
        ChatAttentionLevel.failed,
      );
      expect(
        _entry('a', unread: true, children: 2).level,
        ChatAttentionLevel.unread,
      );
      expect(
        _entry('a', status: AgentChatSessionStatus.running, children: 1).level,
        ChatAttentionLevel.working,
      );
      expect(_entry('a', children: 1).level, ChatAttentionLevel.waitingOnTasks);
      expect(_entry('a').level, ChatAttentionLevel.idle);
    });
  });

  test('a change folds status and requests, keeping read state', () {
    final entry = _entry('a', unread: true);
    final next = entry.folded(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'a',
        'cursor': 4,
        'delta': <String, Object?>{
          'session': <String, Object?>{'status': 'running'},
          'requests': <Object?>[],
        },
      }),
      _at.add(const Duration(minutes: 1)),
    );
    expect(next.status, AgentChatSessionStatus.running);
    expect(next.hasPendingRequests, isFalse);
    expect(next.unread, isTrue);
    expect(next.updatedAt, _at.add(const Duration(minutes: 1)));
  });

  test('workspaces gather only chats that want someone', () {
    final attention = chatWorkspaceAttentionOf(<ChatAttentionEntry>[
      _entry('a', pending: true),
      _entry('b', unread: true, updatedAt: _at.add(const Duration(hours: 1))),
      _entry('c'),
      _entry('d', workspaceId: 'ws-2'),
    ]);
    expect(attention.keys, <String>['ws-1']);
    final ws1 = attention['ws-1']!;
    expect(ws1.level, ChatAttentionLevel.needsInput);
    expect(ws1.needsInput, 1);
    expect(ws1.unread, 1);
    expect(ws1.latestAt, _at.add(const Duration(hours: 1)));
    expect(ws1.description, '1 chat needs input · 1 unread result');
  });

  group('transitions', () {
    test('the first sight of a chat never notifies', () {
      final transitions = ChatAttentionTransitions(now: () => _at);
      expect(
        transitions.next(<String, ChatAttentionEntry>{
          'a': _entry('a', pending: true),
        }),
        isEmpty,
      );
    });

    test('notifies once per transition into needs input, failed or done', () {
      var now = _at;
      final transitions = ChatAttentionTransitions(now: () => now);
      final working = _entry('a', status: AgentChatSessionStatus.running);
      transitions.next(<String, ChatAttentionEntry>{'a': working});

      final asked = transitions.next(<String, ChatAttentionEntry>{
        'a': _entry('a', status: AgentChatSessionStatus.running, pending: true),
      });
      expect(asked.single.$2, ChatAttentionNotice.needsInput);
      expect(
        transitions.next(<String, ChatAttentionEntry>{
          'a': _entry(
            'a',
            status: AgentChatSessionStatus.running,
            pending: true,
          ),
        }),
        isEmpty,
      );

      now = now.add(const Duration(minutes: 5));
      transitions.next(<String, ChatAttentionEntry>{'a': working});
      final done = transitions.next(<String, ChatAttentionEntry>{
        'a': _entry('a', unread: true),
      });
      expect(done.single.$2, ChatAttentionNotice.done);
      expect(
        chatAttentionNoticeMessage(done.single.$1, done.single.$2),
        'Chat a finished.',
      );
    });

    test('a repeat inside the cooldown stays quiet', () {
      var now = _at;
      final transitions = ChatAttentionTransitions(now: () => now);
      final idle = <String, ChatAttentionEntry>{'a': _entry('a')};
      final asking = <String, ChatAttentionEntry>{
        'a': _entry('a', pending: true),
      };
      transitions.next(idle);
      expect(transitions.next(asking), hasLength(1));
      transitions.next(idle);
      now = now.add(const Duration(seconds: 10));
      expect(transitions.next(asking), isEmpty);
      transitions.next(idle);
      now = now.add(const Duration(minutes: 2));
      expect(transitions.next(asking), hasLength(1));
    });

    test('children report through their parent', () {
      final transitions = ChatAttentionTransitions(now: () => _at);
      transitions.next(<String, ChatAttentionEntry>{'child': _entry('child')});
      expect(
        transitions.next(
          <String, ChatAttentionEntry>{'child': _entry('child', pending: true)},
          children: <String>{'child'},
        ),
        isEmpty,
      );
    });
  });
}
