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

    test(
      'waiting needs input and starting is work even with unread results',
      () {
        expect(
          _entry('a', status: AgentChatSessionStatus.waiting).level,
          ChatAttentionLevel.needsInput,
        );
        expect(
          _entry(
            'a',
            status: AgentChatSessionStatus.starting,
            unread: true,
          ).level,
          ChatAttentionLevel.working,
        );
      },
    );
  });

  test('a summary preserves the chat binding and attention state', () {
    final summary = AgentChatSummary(
      chatId: 'a',
      workspaceId: 'ws-1',
      title: 'Work Chat',
      provider: 'codex',
      providerInstanceId: 'codex-work',
      status: AgentChatSessionStatus.running,
      updatedAt: _at,
      tabId: 'tab-a',
      pendingRequestCount: 2,
      openChildTaskCount: 3,
      childNeedsInput: true,
      unread: true,
    );
    final entry = ChatAttentionEntry.fromSummary(summary);
    final expected = ChatAttentionEntry(
      chatId: 'a',
      workspaceId: 'ws-1',
      title: 'Work Chat',
      provider: 'codex',
      status: AgentChatSessionStatus.running,
      updatedAt: _at,
      tabId: 'tab-a',
      hasPendingRequests: true,
      openChildTaskCount: 3,
      childNeedsInput: true,
      unread: true,
    );
    expect(entry, expected);
    expect(entry.hashCode, expected.hashCode);
    expect(<ChatAttentionEntry>{entry, expected}, hasLength(1));
    expect(entry, isNot(_entry('a')));
    expect(entry, isNot('a'));
  });

  test('live children update attention without changing the chat state', () {
    final entry = _entry('a', unread: true, children: 1);
    expect(entry.withChildren((open: 1, needsInput: false)), same(entry));
    final next = entry.withChildren((open: 2, needsInput: true));
    expect(next, _entry('a', unread: true, children: 2, childNeedsInput: true));
    expect(next, isNot(entry));
    expect(next.level, ChatAttentionLevel.needsInput);
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

  test('metadata changes preserve the activity time and pending state', () {
    final entry = _entry('a', pending: true, children: 2, unread: true);
    final next = entry.folded(
      const AgentChatChange(
        chatId: 'a',
        cursor: 5,
        title: 'Renamed Chat',
        provider: 'cursor',
      ),
      _at.add(const Duration(hours: 1)),
    );
    expect(next.title, 'Renamed Chat');
    expect(next.provider, 'cursor');
    expect(next.updatedAt, entry.updatedAt);
    expect(next.hasPendingRequests, isTrue);
    expect(next.openChildTaskCount, 2);
    expect(next.unread, isTrue);
    expect(
      next.folded(const AgentChatChange(chatId: 'a', cursor: 6), _at),
      next,
    );
  });

  test('a new request changes activity time and needs input', () {
    final next = _entry('a').folded(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'a',
        'cursor': 7,
        'delta': <String, Object?>{
          'requests': <Object?>[
            <String, Object?>{
              'requestId': 'request-1',
              'kind': 'file_change_approval',
              'createdAt': _at.toIso8601String(),
            },
          ],
        },
      }),
      _at.add(const Duration(minutes: 2)),
    );
    expect(next.level, ChatAttentionLevel.needsInput);
    expect(next.updatedAt, _at.add(const Duration(minutes: 2)));
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

  test('workspace urgency includes every active state in priority order', () {
    final cases = <(ChatWorkspaceAttention, ChatAttentionLevel)>[
      (ChatWorkspaceAttention(), ChatAttentionLevel.idle),
      (
        ChatWorkspaceAttention(waitingOnTasks: 1),
        ChatAttentionLevel.waitingOnTasks,
      ),
      (
        ChatWorkspaceAttention(working: 1, waitingOnTasks: 1),
        ChatAttentionLevel.working,
      ),
      (
        ChatWorkspaceAttention(unread: 1, working: 1),
        ChatAttentionLevel.unread,
      ),
      (ChatWorkspaceAttention(failed: 1, unread: 1), ChatAttentionLevel.failed),
      (
        ChatWorkspaceAttention(needsInput: 1, failed: 1),
        ChatAttentionLevel.needsInput,
      ),
    ];
    for (final (attention, level) in cases) {
      expect(attention.level, level);
    }
  });

  test(
    'workspace tooltips describe all counts with singular and plural copy',
    () {
      expect(ChatWorkspaceAttention().description, isEmpty);
      expect(
        ChatWorkspaceAttention(
          needsInput: 1,
          failed: 1,
          unread: 1,
          working: 1,
          waitingOnTasks: 1,
        ).description,
        '1 chat needs input · 1 chat stopped · 1 unread result · '
        '1 chat working · 1 waiting on delegated tasks',
      );
      expect(
        ChatWorkspaceAttention(
          needsInput: 2,
          failed: 2,
          unread: 2,
          working: 2,
          waitingOnTasks: 2,
        ).description,
        '2 chats need input · 2 chats stopped · 2 unread results · '
        '2 chats working · 2 waiting on delegated tasks',
      );
    },
  );

  test('workspace aggregates count states and keep the latest active time', () {
    final entries = <ChatAttentionEntry>[
      _entry(
        'input',
        pending: true,
        updatedAt: _at.add(const Duration(hours: 1)),
      ),
      _entry('failed', status: AgentChatSessionStatus.error),
      _entry('unread', unread: true),
      _entry('working', status: AgentChatSessionStatus.running),
      _entry('tasks', children: 2),
      _entry('idle', updatedAt: _at.add(const Duration(days: 1))),
      _entry('other', workspaceId: 'ws-2', unread: true),
    ];
    final attention = chatWorkspaceAttentionOf(entries);
    final expected = ChatWorkspaceAttention(
      needsInput: 1,
      failed: 1,
      unread: 1,
      working: 1,
      waitingOnTasks: 1,
      latestAt: _at.add(const Duration(hours: 1)),
    );
    expect(attention['ws-1'], expected);
    expect(attention['ws-1']!.hashCode, expected.hashCode);
    expect(<ChatWorkspaceAttention>{
      attention['ws-1']!,
      expected,
    }, hasLength(1));
    expect(attention['ws-2'], ChatWorkspaceAttention(unread: 1, latestAt: _at));
    expect(expected, isNot(attention['ws-2']));
    expect(expected, isNot('ws-1'));
    expect(() => attention.clear(), throwsUnsupportedError);
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
