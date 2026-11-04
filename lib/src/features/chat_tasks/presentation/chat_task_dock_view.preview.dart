import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_dock_view.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_input_banner.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_outcome_card.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

final DateTime _now = DateTime.utc(2026, 10, 12, 12);

AgentChatTask _task(
  String id,
  AgentChatTaskStatus status, {
  required String title,
  AgentChatTaskAttention attention = AgentChatTaskAttention.none,
  AgentChatTaskResult? result,
  AgentChatTaskFailure? failure,
}) => AgentChatTask(
  id: id,
  status: status,
  createdAt: _now.subtract(const Duration(minutes: 12)),
  updatedAt: _now.subtract(const Duration(minutes: 1)),
  completedAt: status.settled
      ? _now.subtract(const Duration(minutes: 1))
      : null,
  title: title,
  parentChatId: 'chat-planner',
  childChatId: 'chat-$id',
  workspaceId: 'ws-parser',
  projectId: 'alera',
  provider: 'codex',
  model: 'gpt-5',
  attention: attention,
  result: result,
  failure: failure,
  labels: const AgentChatTaskLabels(
    parentChatTitle: 'Planner',
    projectName: 'Alera',
    workspaceName: 'parser-port',
  ),
);

final List<AgentChatTask> _tasks = <AgentChatTask>[
  _task(
    'task-1',
    AgentChatTaskStatus.needsInput,
    title: 'Port the parser to Rust',
    attention: AgentChatTaskAttention.needsInput,
  ),
  _task('task-2', AgentChatTaskStatus.running, title: 'Review the migration'),
  _task(
    'task-3',
    AgentChatTaskStatus.completed,
    title: 'Write release notes',
    result: const AgentChatTaskResult(
      text: 'Release notes are in docs/releases/0.107.md. Two breaking changes are called out at the top.',
    ),
  ),
  _task(
    'task-4',
    AgentChatTaskStatus.failed,
    title: 'Benchmark the tokenizer',
    failure: const AgentChatTaskFailure(
      message: 'cargo bench failed: missing criterion feature.',
    ),
  ),
];

ChatTaskDockActions _actions() => ChatTaskDockActions(
  onView: (_) {},
  onStop: (_) {},
  onOpenChat: (_) {},
  onViewAll: () {},
);

@AleraPreview(name: 'Tasks dock', group: 'Chat tasks', size: Size(560, 360))
Widget chatTaskDockPreview() => SizedBox(
  width: 520,
  child: Column(
    mainAxisSize: .min,
    spacing: AleraTokens.space8,
    children: <Widget>[
      ChatTaskInputBanner(
        task: _tasks.first,
        answering: false,
        onAnswerHere: () {},
        onOpenChat: () {},
      ),
      ChatTaskDockView(
        tasks: _tasks,
        expanded: false,
        onExpandedChanged: (_) {},
        now: () => _now,
        placeOf: agentChatTaskPlaceLabel,
        actions: _actions(),
      ),
      ChatTaskDockView(
        tasks: _tasks,
        expanded: true,
        onExpandedChanged: (_) {},
        now: () => _now,
        placeOf: agentChatTaskPlaceLabel,
        actions: _actions(),
        maxRows: 3,
      ),
    ],
  ),
);

@AleraPreview(name: 'Task outcomes', group: 'Chat tasks', size: Size(560, 320))
Widget chatTaskOutcomePreview() => SizedBox(
  width: 520,
  child: Column(
    mainAxisSize: .min,
    children: <Widget>[
      ChatTaskOriginRow(
        label: agentChatTaskOriginLabel(_tasks[1]),
        onOpenParent: () {},
        onView: () {},
      ),
      ChatTaskOutcomeCard(
        task: _tasks[2],
        now: _now,
        onView: () {},
        onOpenChat: () {},
      ),
      ChatTaskOutcomeCard(task: _tasks[3], now: _now, onView: () {}),
      const ChatMessageSenderRow(
        senderTitle: 'Planner',
        senderPlace: 'Alera / main',
      ),
    ],
  ),
);
