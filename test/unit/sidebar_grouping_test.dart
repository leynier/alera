import 'package:alera/src/features/projects/application/projects_state.dart';
import 'package:alera/src/features/projects/application/sidebar_grouping.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

ChatSummary _chat({
  required String id,
  required String projectId,
  String title = 'chat',
  required DateTime updatedAt,
}) {
  return ChatSummary(
    id: id,
    projectId: projectId,
    title: title,
    model: 'gpt-test',
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('groupChatsByRecency', () {
    final now = DateTime(2026, 5, 13, 14, 30);

    test('returns empty list for empty input', () {
      expect(groupChatsByRecency(const <ChatSummary>[], now: now), isEmpty);
    });

    test('buckets a chat updated today into Today', () {
      final today = _chat(
        id: 'a',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 13, 9),
      );
      final groups = groupChatsByRecency(<ChatSummary>[today], now: now);
      expect(groups, hasLength(1));
      expect(groups.first.bucket, ChatRecencyBucket.today);
      expect(groups.first.chats, <ChatSummary>[today]);
    });

    test('buckets yesterday vs this week vs older correctly', () {
      final today = _chat(
        id: 't',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 13, 1),
      );
      final yesterday = _chat(
        id: 'y',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 12, 23),
      );
      final thisWeek = _chat(
        id: 'w',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 9, 10),
      );
      final older = _chat(
        id: 'o',
        projectId: 'p',
        updatedAt: DateTime(2026, 4, 1, 10),
      );

      final groups = groupChatsByRecency(<ChatSummary>[
        today,
        yesterday,
        thisWeek,
        older,
      ], now: now);

      expect(groups.map((g) => g.bucket).toList(), <ChatRecencyBucket>[
        ChatRecencyBucket.today,
        ChatRecencyBucket.yesterday,
        ChatRecencyBucket.thisWeek,
        ChatRecencyBucket.older,
      ]);
      expect(groups[0].chats.single.id, 't');
      expect(groups[1].chats.single.id, 'y');
      expect(groups[2].chats.single.id, 'w');
      expect(groups[3].chats.single.id, 'o');
    });

    test('omits buckets with no chats', () {
      final older = _chat(
        id: 'o',
        projectId: 'p',
        updatedAt: DateTime(2024, 1, 1),
      );
      final groups = groupChatsByRecency(<ChatSummary>[older], now: now);
      expect(groups, hasLength(1));
      expect(groups.single.bucket, ChatRecencyBucket.older);
    });

    test('preserves input order inside a bucket', () {
      final a = _chat(
        id: 'a',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 13, 12),
      );
      final b = _chat(
        id: 'b',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 13, 10),
      );
      final c = _chat(
        id: 'c',
        projectId: 'p',
        updatedAt: DateTime(2026, 5, 13, 8),
      );
      final groups = groupChatsByRecency(<ChatSummary>[a, b, c], now: now);
      expect(groups.single.chats.map((c) => c.id).toList(), <String>[
        'a',
        'b',
        'c',
      ]);
    });

    test('labels are sentence case', () {
      expect(chatRecencyBucketLabel(ChatRecencyBucket.today), 'Today');
      expect(chatRecencyBucketLabel(ChatRecencyBucket.yesterday), 'Yesterday');
      expect(chatRecencyBucketLabel(ChatRecencyBucket.thisWeek), 'This week');
      expect(chatRecencyBucketLabel(ChatRecencyBucket.older), 'Older');
    });
  });

  group('ProjectsState search and pinned helpers', () {
    final project1 = Project(
      id: 'p1',
      name: 'Alera',
      repoPath: '/tmp/p1',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final project2 = Project(
      id: 'p2',
      name: 'Other',
      repoPath: '/tmp/p2',
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    );
    final chatA = _chat(
      id: 'a',
      projectId: 'p1',
      title: 'Fix login bug',
      updatedAt: DateTime(2026, 5, 13),
    );
    final chatB = _chat(
      id: 'b',
      projectId: 'p1',
      title: 'Refactor sidebar',
      updatedAt: DateTime(2026, 5, 12),
    );
    final chatC = _chat(
      id: 'c',
      projectId: 'p2',
      title: 'Fix sidebar typo',
      updatedAt: DateTime(2026, 5, 11),
    );

    final state = ProjectsState(
      projects: <Project>[project1, project2],
      chatsByProject: <String, List<ChatSummary>>{
        'p1': <ChatSummary>[chatA, chatB],
        'p2': <ChatSummary>[chatC],
      },
    );

    test('filteredChatsFor returns full list when query is empty', () {
      final next = state.copyWith(searchQuery: '');
      expect(next.filteredChatsFor('p1'), <ChatSummary>[chatA, chatB]);
    });

    test('filteredChatsFor matches case-insensitive substrings on title', () {
      final next = state.copyWith(searchQuery: 'FIX');
      expect(next.filteredChatsFor('p1'), <ChatSummary>[chatA]);
      expect(next.filteredChatsFor('p2'), <ChatSummary>[chatC]);
    });

    test('globalSearchResults groups by project and skips empty groups', () {
      final next = state.copyWith(searchQuery: 'sidebar');
      final results = next.globalSearchResults();
      expect(results, hasLength(2));
      expect(results[0].project.id, 'p1');
      expect(results[0].chats.map((c) => c.id), <String>['b']);
      expect(results[1].project.id, 'p2');
      expect(results[1].chats.map((c) => c.id), <String>['c']);
    });

    test('globalSearchResults is empty when query is empty', () {
      expect(state.globalSearchResults(), isEmpty);
    });

    test('pinnedChats respects persisted order', () {
      final next = state.copyWith(
        pinnedChatIds: <String>{'a', 'c'},
        pinnedChatOrder: <String>['c', 'a'],
      );
      final pinned = next.pinnedChats();
      expect(pinned.map((c) => c.id).toList(), <String>['c', 'a']);
    });

    test('pinnedChats appends ids missing from the order list', () {
      final next = state.copyWith(
        pinnedChatIds: <String>{'a', 'b', 'c'},
        pinnedChatOrder: <String>['a'],
      );
      final pinned = next.pinnedChats();
      expect(pinned.first.id, 'a');
      expect(pinned.length, 3);
      // The two ids missing from the order list must still appear.
      expect(pinned.map((c) => c.id).toSet(), <String>{'a', 'b', 'c'});
    });

    test('pinnedChats skips ids whose chat no longer exists', () {
      final next = state.copyWith(
        pinnedChatIds: <String>{'a', 'ghost'},
        pinnedChatOrder: <String>['ghost', 'a'],
      );
      expect(next.pinnedChats().map((c) => c.id).toList(), <String>['a']);
    });
  });
}
