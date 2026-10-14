import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/runs/infra/foreground_board_watch.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_task_parent_activity.g.dart';

/// Every unsettled task on the runtime: what parent chats are waiting on.
const AgentChatTaskQuery chatTaskOpenQuery = AgentChatTaskQuery(
  statuses: <AgentChatTaskStatus>{
    AgentChatTaskStatus.preparing,
    AgentChatTaskStatus.running,
    AgentChatTaskStatus.needsInput,
    AgentChatTaskStatus.cancelRequested,
  },
  limit: chatTaskAttentionLimit,
);

/// What a parent chat waits on, from the tasks it delegated. Children report
/// through their parent, so a child that needs input raises the parent.
class const ChatTaskParentActivity({
  final int open = 0,
  final int needsInput = 0,
  final int failed = 0,
}) {
  static const ChatTaskParentActivity none = ChatTaskParentActivity();

  bool get waitingOnTasks => open > 0;

  bool get childNeedsInput => needsInput > 0;

  @override
  bool operator ==(Object other) =>
      other is ChatTaskParentActivity &&
      other.open == open &&
      other.needsInput == needsInput &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(open, needsInput, failed);
}

/// Folds the open and attention lists into one entry per parent chat. A task
/// in both lists counts once; tasks a person owns have no parent and are
/// left to Activity.
Map<String, ChatTaskParentActivity> chatTaskParentActivities({
  required Iterable<AgentChatTask> open,
  required Iterable<AgentChatTask> attention,
}) {
  final tasks = <String, AgentChatTask>{
    for (final task in open) task.id: task,
    for (final task in attention) task.id: task,
  };
  final counts = <String, (int, int, int)>{};
  for (final task in tasks.values) {
    final parent = task.parentChatId;
    if (parent == null) continue;
    final (opened, waiting, failed) = counts[parent] ?? (0, 0, 0);
    final needsInput =
        task.status == AgentChatTaskStatus.needsInput ||
        task.attention == AgentChatTaskAttention.needsInput;
    counts[parent] = (
      opened + (task.status.settled ? 0 : 1),
      waiting + (needsInput ? 1 : 0),
      failed + (task.attention == AgentChatTaskAttention.failed ? 1 : 0),
    );
  }
  return Map<String, ChatTaskParentActivity>.unmodifiableOf(
    <String, ChatTaskParentActivity>{
      for (final MapEntry(:key, value: (opened, waiting, failed))
          in counts.entries)
        key: ChatTaskParentActivity(
          open: opened,
          needsInput: waiting,
          failed: failed,
        ),
    },
  );
}

/// The child chats of every task the lists name, so attention notices can
/// leave children to their parent.
Set<String> chatTaskChildChatIds(Iterable<AgentChatTask> tasks) => <String>{
  for (final task in tasks)
    if (task.parentChatId != null) ?task.childChatId,
};

/// One runtime-wide list of unsettled tasks, read again on every change that
/// may touch it. Hidden windows do no reads.
@Riverpod(retry: chatTaskNoRetry)
Stream<AgentChatTaskPage> chatTaskOpenTasks(Ref ref) {
  final repository = ref.watch(chatTaskRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository.watchTasks(chatTaskOpenQuery),
  );
}

/// What each parent chat waits on, keyed by parent chat id. Empty on a
/// runtime without chat tasks or while a read fails.
@riverpod
Map<String, ChatTaskParentActivity> chatTaskParentActivity(Ref ref) {
  if (ref.watch(chatTasksSupportedProvider).value != true) {
    return const <String, ChatTaskParentActivity>{};
  }
  return chatTaskParentActivities(
    open: ref.watch(chatTaskOpenTasksProvider).value?.tasks ?? const [],
    attention: ref.watch(chatTaskAttentionProvider).value?.tasks ?? const [],
  );
}
