import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_location.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_attention_control.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_tasks_section.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening a task shows Chat Tasks and keeps the other sections', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier)
      ..open(ActivitySection.runs)
      ..selectRun('run-1')
      ..openChatTask('task-7');
    final location = container.read(activityNavigationProvider);
    expect(location.visible, isTrue);
    expect(location.section, ActivitySection.chatTasks);
    expect(location.chatTasks.taskId, 'task-7');
    expect(location.runs.runId, 'run-1');

    navigation.showSection(ActivitySection.runs);
    navigation.showSection(ActivitySection.chatTasks);
    expect(
      container.read(activityNavigationProvider).chatTasks.taskId,
      'task-7',
    );
  });

  test('filters start the list from its first page again', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier)
      ..showMoreChatTasks()
      ..showMoreChatTasks();
    expect(
      container.read(activityNavigationProvider).chatTasks.limit,
      chatTasksPageSize * 3,
    );
    navigation
      ..filterChatTaskProject('project-1')
      ..filterChatTaskWorkspace('ws-1')
      ..filterChatTaskBucket(AgentChatTaskBucket.attention);
    var location = container.read(activityNavigationProvider).chatTasks;
    expect(location.limit, chatTasksPageSize);
    expect(location.filtered, isTrue);
    navigation.filterChatTaskProject('project-2');
    location = container.read(activityNavigationProvider).chatTasks;
    expect(location.workspaceId, isNull, reason: 'a project resets it');
    navigation.clearChatTaskFilters();
    expect(
      container.read(activityNavigationProvider).chatTasks.filtered,
      isFalse,
    );
  });

  test('each group maps to the runtime filters', () {
    expect(
      chatTaskQueryFor(
        const ChatTasksLocation(bucket: AgentChatTaskBucket.attention),
      ).toJson(),
      <String, Object?>{'attention': true, 'limit': chatTasksPageSize},
    );
    expect(
      chatTaskQueryFor(
        const ChatTasksLocation(
          bucket: AgentChatTaskBucket.active,
          projectId: 'project-1',
        ),
      ).toJson(),
      <String, Object?>{
        'statuses': <String>[
          'preparing',
          'running',
          'needs_input',
          'cancel_requested',
        ],
        'projectId': 'project-1',
        'limit': chatTasksPageSize,
      },
    );
    expect(
      chatTaskQueryFor(
        const ChatTasksLocation(bucket: AgentChatTaskBucket.history),
      ).statuses,
      <AgentChatTaskStatus>{
        AgentChatTaskStatus.completed,
        AgentChatTaskStatus.failed,
        AgentChatTaskStatus.interrupted,
        AgentChatTaskStatus.cancelled,
      },
    );
  });

  test('chat tasks waiting or failed count as blocking attention', () {
    const attention = ActivityAttention(questions: 1, chatTasks: 2);
    expect(attention.total, 3);
    expect(attention.countFor(ActivitySection.chatTasks), 2);
    expect(attention.hasBlockingWork, isTrue);
    expect(
      activityAttentionTooltip(
        const ActivityAttention(
          runs: 1,
          unavailable: <ActivitySection>{ActivitySection.chatTasks},
        ),
      ),
      'Open Activity · 1 item needs attention · Chat Tasks unavailable',
    );
    expect(
      const ActivityAttention(chatTasks: 1) ==
          const ActivityAttention(chatTasks: 2),
      isFalse,
    );
  });
}
