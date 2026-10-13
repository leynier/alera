import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_detail_view.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_list.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

final DateTime _now = DateTime.utc(2026, 10, 12, 12);

AgentChatTask _task(
  String id,
  AgentChatTaskStatus status, {
  String title = 'Port the parser to Rust',
  AgentChatTaskAttention attention = AgentChatTaskAttention.none,
  AgentChatTaskResult? result,
  int pendingRequestCount = 0,
}) => AgentChatTask(
  id: id,
  status: status,
  createdAt: _now.subtract(const Duration(minutes: 42)),
  updatedAt: _now.subtract(const Duration(minutes: 3)),
  title: title,
  brief: 'Port lib/parser.dart to a Rust crate with the same tests, then report what changed.',
  parentChatId: 'chat-planner',
  childChatId: 'chat-$id',
  workspaceId: 'ws-parser',
  projectId: 'alera',
  provider: 'codex',
  providerInstanceId: 'codex',
  model: 'gpt-5',
  runtimeMode: AgentChatRuntimeMode.autoAcceptEdits,
  target: const AgentChatTaskNewWorkspaceTarget(
    projectId: 'alera',
    hostId: agentChatLocalHostId,
    mode: AgentChatWorkspaceMode.worktree,
  ),
  attention: attention,
  pendingRequestCount: pendingRequestCount,
  result: result,
  actor: 'agent:chat-planner',
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
    attention: AgentChatTaskAttention.needsInput,
    pendingRequestCount: 1,
  ),
  _task('task-2', AgentChatTaskStatus.running, title: 'Review the migration'),
  _task(
    'task-3',
    AgentChatTaskStatus.completed,
    title: 'Write release notes',
    result: const AgentChatTaskResult(text: 'Release notes are in docs/.'),
  ),
];

@AleraPreview(name: 'Task list', group: 'Chat tasks', size: Size(360, 520))
Widget chatTaskListPreview() => SizedBox(
  width: 340,
  height: 500,
  child: ChatTaskList(
    tasks: _tasks,
    now: _now,
    selectedTaskId: 'task-2',
    onSelect: (_) {},
    placeOf: agentChatTaskPlaceLabel,
    filters: const SizedBox.shrink(),
    emptyMessage: 'No chat tasks yet.',
  ),
);

@AleraPreview(name: 'Task detail', group: 'Chat tasks', size: Size(640, 720))
Widget chatTaskDetailPreview() => SizedBox(
  width: 600,
  height: 680,
  child: ChatTaskDetailView(
    task: _tasks.first,
    now: _now,
    place: 'Alera / parser-port',
    requests: <AgentChatTaskRequest>[
      AgentChatTaskRequest(
        chatId: 'chat-task-1',
        taskId: 'task-1',
        request: AgentChatRequest(
          id: 'request-1',
          kind: AgentChatRequestKind.commandExecutionApproval,
          createdAt: _now,
          command: 'cargo test -p parser',
          decisions: const <AgentChatApprovalDecision>[
            AgentChatApprovalDecision.accept,
            AgentChatApprovalDecision.decline,
          ],
        ),
      ),
    ],
    actions: ChatTaskDetailActions(
      onOpenChat: () {},
      onOpenWorkspace: () {},
      onOpenParentChat: () {},
      onWait: () {},
      onCancel: () {},
      onDecision: (_, _) {},
    ),
  ),
);

@AleraPreview(name: 'Chat dock', group: 'Chat tasks', size: Size(520, 200))
Widget chatTaskDockPreview() => SizedBox(
  width: 480,
  child: Column(
    mainAxisSize: .min,
    children: <Widget>[
      ChatTaskDockView(
        tasks: _tasks.take(2).toList(),
        total: 4,
        onView: (_) {},
      ),
      const ChatMessageSenderRow(
        senderTitle: 'Planner',
        senderPlace: 'Alera / main',
      ),
    ],
  ),
);
