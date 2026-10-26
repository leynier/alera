import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _wireTask([Map<String, Object?> extra = const {}]) =>
    <String, Object?>{
      'taskId': 'task-1',
      'kind': 'delegate',
      'status': 'needs_input',
      'parentTaskId': 'task-0',
      'rootTaskId': 'task-0',
      'depth': 1,
      'parentChatId': 'chat-parent',
      'childChatId': 'chat-child',
      'workspaceId': 'ws-2',
      'projectId': 'project-2',
      'hostId': 'host-a',
      'target': <String, Object?>{
        'newWorkspace': <String, Object?>{
          'projectId': 'project-2',
          'hostId': 'host-a',
          'mode': 'shared',
          'setup': 'deferred',
          'name': 'Docs',
        },
      },
      'title': 'Write docs',
      'brief': '\n  Update the readme\nthen the changelog',
      'notify': 'settled_only',
      'attention': true,
      'attentionKind': 'needs_input',
      'resultDelivery': 'notified',
      'pendingRequestCount': 2,
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'model': 'gpt-5',
      'runtimeMode': 'auto-accept-edits',
      'labels': <String, Object?>{
        'parentChatTitle': 'Planner',
        'childChatTitle': 'Docs Writer',
        'projectName': 'Alera',
        'workspaceName': 'docs',
        'hostLabel': 'Build Box',
      },
      'actor': 'agent:chat-parent',
      'createdAt': '2026-10-12T10:00:00Z',
      'updatedAt': '2026-10-12T10:05:00Z',
      ...extra,
    };

void main() {
  test('reads the runtime task projection', () {
    final task = AgentChatTask.fromJson(_wireTask());
    expect(task.id, 'task-1');
    expect(task.status, AgentChatTaskStatus.needsInput);
    expect(task.kind, AgentChatTaskKind.delegate);
    expect(task.parentTaskId, 'task-0');
    expect(task.rootTaskId, 'task-0');
    expect(task.depth, 1);
    expect(task.parentChatId, 'chat-parent');
    expect(task.childChatId, 'chat-child');
    expect(task.notify, AgentChatTaskNotify.settledOnly);
    expect(task.delivery, AgentChatTaskDelivery.notified);
    expect(task.attention, AgentChatTaskAttention.needsInput);
    expect(task.pendingRequestCount, 2);
    expect(task.runtimeMode, AgentChatRuntimeMode.autoAcceptEdits);
    expect(task.labels.childChatTitle, 'Docs Writer');
    expect(task.ownedByPerson, isFalse);
    final target = task.target! as AgentChatTaskNewWorkspaceTarget;
    expect(target.mode, AgentChatWorkspaceMode.shared);
    expect(target.setup, AgentChatWorkspaceSetup.deferred);
    expect(target.name, 'Docs');
    expect(task.displayTitle, 'Write docs');
    expect(agentChatTaskPlaceLabel(task), 'Alera / docs · Build Box');
  });

  test('accepts the delivery alias and camelCase tokens', () {
    final task = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{
        'resultDelivery': null,
        'delivery': 'acknowledged',
        'status': 'cancelRequested',
      }),
    );
    expect(task.delivery, AgentChatTaskDelivery.acknowledged);
    expect(task.status, AgentChatTaskStatus.cancelRequested);
  });

  test('derives attention when the runtime leaves the flag out', () {
    AgentChatTask read(String status, String delivery) =>
        AgentChatTask.fromJson(
          _wireTask(<String, Object?>{
            'attention': null,
            'attentionKind': null,
            'status': status,
            'resultDelivery': delivery,
          }),
        );
    expect(
      read('needs_input', 'pending').attention,
      AgentChatTaskAttention.needsInput,
    );
    expect(read('failed', 'pending').attention, AgentChatTaskAttention.failed);
    expect(
      read('failed', 'acknowledged').attention,
      AgentChatTaskAttention.none,
    );
    expect(read('completed', 'pending').attention, AgentChatTaskAttention.none);
  });

  test('an explicit false flag wins over the status', () {
    final task = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{'attention': false, 'status': 'failed'}),
    );
    expect(task.attention, AgentChatTaskAttention.none);
    expect(AgentChatTaskBucket.of(task), AgentChatTaskBucket.history);
  });

  test('an unknown status stays active instead of hiding in History', () {
    final task = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{'status': 'teleporting', 'attention': false}),
    );
    expect(task.status, AgentChatTaskStatus.running);
    expect(AgentChatTaskBucket.of(task), AgentChatTaskBucket.active);
  });

  test('result and error read the object and the bare string forms', () {
    final task = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{
        'status': 'completed',
        'result': <String, Object?>{
          'text': 'Done.',
          'truncated': true,
          'turnId': 'turn-9',
        },
        'error': 'Provider exited.',
      }),
    );
    expect(task.result?.text, 'Done.');
    expect(task.result?.truncated, isTrue);
    expect(task.result?.turnId, 'turn-9');
    expect(task.failure?.message, 'Provider exited.');
    expect(task.failure?.code, isNull);
  });

  test('the title falls back to the first brief line, then the id', () {
    final fromBrief = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{'title': null}),
    );
    expect(fromBrief.displayTitle, 'Update the readme');
    final long = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{'title': null, 'brief': 'x' * 200}),
    );
    expect(long.displayTitle.length, 120);
    expect(long.displayTitle.endsWith('…'), isTrue);
    final bare = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{'title': null, 'brief': null}),
    );
    expect(bare.displayTitle, 'Task task-1');
  });

  test('a workspace target fills the workspace when the row omits it', () {
    final task = AgentChatTask.fromJson(
      _wireTask(<String, Object?>{
        'workspaceId': null,
        'target': <String, Object?>{
          'workspace': <String, Object?>{'workspaceId': 'ws-7'},
        },
      }),
    );
    expect(task.workspaceId, 'ws-7');
    expect(agentChatTaskTargetLabel(task.target), 'New Chat');
  });

  test('targets round-trip through their wire form', () {
    const targets = <AgentChatTaskTarget>[
      AgentChatTaskChatTarget('chat-1'),
      AgentChatTaskWorkspaceTarget('ws-1'),
      AgentChatTaskNewWorkspaceTarget(
        projectId: 'project-1',
        hostId: agentChatLocalHostId,
        mode: AgentChatWorkspaceMode.worktree,
        branch: 'feature/docs',
        sourceBranch: 'main',
        reuseExistingBranch: true,
        parentWorkspaceId: 'ws-parent',
      ),
    ];
    for (final target in targets) {
      final parsed = AgentChatTaskTarget.fromJson(target.toJson())!;
      expect(parsed.toJson(), target.toJson());
    }
    expect(targets.last.toJson(), <String, Object?>{
      'newWorkspace': <String, Object?>{
        'projectId': 'project-1',
        'hostId': 'local',
        'mode': 'worktree',
        'branch': 'feature/docs',
        'sourceBranch': 'main',
        'reuseExistingBranch': true,
        'parentWorkspaceId': 'ws-parent',
        'setup': 'inline',
      },
    });
    expect(AgentChatTaskTarget.fromJson(<String, Object?>{}), isNull);
  });

  test('rows without a task id are skipped in lists', () {
    final page = AgentChatTaskPage.fromJson(<String, Object?>{
      'tasks': <Object?>[
        _wireTask(),
        <String, Object?>{'status': 'running'},
        'garbage',
      ],
      'nextCursor': 'c-2',
    });
    expect(page.tasks.map((task) => task.id), <String>['task-1']);
    expect(page.nextCursor, 'c-2');
  });

  test('labels read as title-case UI copy', () {
    expect(AgentChatTaskStatus.values.map(agentChatTaskStatusLabel), <String>[
      'Preparing',
      'Running',
      'Needs Input',
      'Completed',
      'Failed',
      'Interrupted',
      'Cancelling',
      'Cancelled',
    ]);
    expect(agentChatTaskActorLabel('mobile:device-1'), 'Phone');
    expect(agentChatTaskActorLabel('agent:chat-1'), 'Agent');
    expect(agentChatTaskActorLabel(null), 'Unknown');
    final now = DateTime.utc(2026, 10, 12, 12);
    expect(agentChatTaskAgeLabel(now, now), 'just now');
    expect(
      agentChatTaskAgeLabel(now.subtract(const Duration(minutes: 5)), now),
      '5m ago',
    );
    expect(
      agentChatTaskAgeLabel(now.subtract(const Duration(days: 9)), now),
      '2026-10-03',
    );
  });
}
