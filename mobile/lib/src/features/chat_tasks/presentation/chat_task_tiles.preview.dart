import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_body.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';

final DateTime _now = DateTime.utc(2026, 10, 12, 12);

AgentChatTask _task(
  String id,
  AgentChatTaskStatus status, {
  String title = 'Port the parser to Rust',
  AgentChatTaskAttention attention = AgentChatTaskAttention.none,
  AgentChatTaskResult? result,
}) => AgentChatTask(
  id: id,
  status: status,
  createdAt: _now.subtract(const Duration(minutes: 40)),
  updatedAt: _now.subtract(const Duration(minutes: 2)),
  title: title,
  brief: 'Port lib/parser.dart to a Rust crate and report what changed.',
  parentChatId: 'chat-planner',
  childChatId: 'chat-$id',
  workspaceId: 'ws-parser',
  provider: 'claudeAgent',
  model: 'opus',
  attention: attention,
  result: result,
  actor: 'mobile:phone-1',
  labels: const AgentChatTaskLabels(
    parentChatTitle: 'Planner',
    projectName: 'Alera',
    workspaceName: 'parser-port',
  ),
);

@AleraPreview(name: 'Task Rows', group: 'Chat Tasks')
Widget chatTaskTilesPreview() => ListView(
  children: <Widget>[
    for (final task in <AgentChatTask>[
      _task(
        'task-1',
        AgentChatTaskStatus.needsInput,
        attention: AgentChatTaskAttention.needsInput,
      ),
      _task('task-2', AgentChatTaskStatus.running, title: 'Review migration'),
      _task('task-3', AgentChatTaskStatus.failed, title: 'Fix flaky test'),
    ])
      ChatTaskTile(
        task: task,
        place: 'Alera / parser-port',
        now: _now,
        onTap: () {},
      ),
  ],
);

@AleraPreview(name: 'Task Detail', group: 'Chat Tasks')
Widget chatTaskDetailPreview() => ChatTaskDetailBody(
  task: _task(
    'task-4',
    AgentChatTaskStatus.completed,
    result: const AgentChatTaskResult(
      text: 'The parser now lives in rust/parser with all 41 tests passing.',
    ),
  ),
  now: _now,
  place: 'Alera / parser-port',
  callbacks: ChatTaskDetailCallbacks(
    onOpenChat: () {},
    onOpenWorkspace: () {},
    onOpenParentChat: () {},
    onFollowUp: () {},
  ),
);

@AleraPreview(name: 'Chat Dock', group: 'Chat Tasks')
Widget chatTaskDockPreview() => Padding(
  padding: AleraTokens.contentPadding,
  child: Column(
    children: <Widget>[
      ChatTaskDockView(
        tasks: <AgentChatTask>[
          _task('task-5', AgentChatTaskStatus.running),
          _task(
            'task-6',
            AgentChatTaskStatus.needsInput,
            attention: AgentChatTaskAttention.needsInput,
          ),
        ],
        total: 3,
        onView: (_) {},
      ),
      const ChatMessageSenderRow(senderTitle: 'Planner'),
    ],
  ),
);
