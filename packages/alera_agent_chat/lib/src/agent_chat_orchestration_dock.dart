import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';

class const AgentChatTaskDockSummary({
  final int running = 0,
  final int needsInput = 0,
  final int failed = 0,
  final int done = 0,
}) {
  factory of(Iterable<AgentChatTask> tasks) {
    var running = 0;
    var needsInput = 0;
    var failed = 0;
    var done = 0;
    for (final task in tasks) {
      if (task.status == .needsInput || task.attention == .needsInput) {
        needsInput++;
      } else if (task.status == .failed || task.status == .interrupted) {
        failed++;
      } else if (task.status.settled) {
        done++;
      } else {
        running++;
      }
    }
    return AgentChatTaskDockSummary(
      running: running,
      needsInput: needsInput,
      failed: failed,
      done: done,
    );
  }

  int get open => running + needsInput;
  int get total => open + failed + done;
  bool get isEmpty => total == 0;
}

String agentChatTaskDockSummaryLabel(AgentChatTaskDockSummary summary) =>
    <String>[
      'Tasks',
      if (summary.running > 0) '${summary.running} running',
      if (summary.needsInput > 0) '${summary.needsInput} needs input',
      if (summary.failed > 0) '${summary.failed} failed',
      if (summary.done > 0) '${summary.done} done',
    ].join(' · ');

List<AgentChatTask> agentChatTaskDockOrder(Iterable<AgentChatTask> tasks) {
  final indexed = tasks.indexed.toList();
  int rank(AgentChatTask task) =>
      task.status == .needsInput || task.attention == .needsInput
      ? 0
      : task.attention == .failed
      ? 1
      : !task.status.settled
      ? 2
      : 3;
  indexed.sort((left, right) {
    final priority = rank(left.$2).compareTo(rank(right.$2));
    if (priority != 0) return priority;
    final recency = right.$2.updatedAt.compareTo(left.$2.updatedAt);
    return recency == 0 ? left.$1.compareTo(right.$1) : recency;
  });
  return List.unmodifiableOf(indexed.map((entry) => entry.$2));
}

Duration agentChatTaskElapsed(AgentChatTask task, DateTime now) {
  final end = task.status.settled ? task.completedAt ?? task.updatedAt : now;
  final elapsed = end.difference(task.createdAt);
  return elapsed.isNegative ? Duration.zero : elapsed;
}
