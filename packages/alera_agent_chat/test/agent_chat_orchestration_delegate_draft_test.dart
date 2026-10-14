import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('every target needs its own explicit choice', () {
    const draft = AgentChatDelegateDraft();
    expect(draft.problem, 'Describe the task.');
    final described = draft.copyWith(task: '  Review the diff  ');
    expect(described.problem, 'Choose a workspace.');
    expect(
      described.copyWith(targetKind: AgentChatTaskTargetKind.chat).problem,
      'Choose a chat.',
    );
    expect(
      described
          .copyWith(targetKind: AgentChatTaskTargetKind.newWorkspace)
          .problem,
      'Choose a project.',
    );
    expect(described.copyWith(workspaceId: 'ws-1').problem, 'Choose an agent.');
    expect(
      described
          .copyWith(targetKind: AgentChatTaskTargetKind.chat, chatId: 'chat-1')
          .problem,
      isNull,
      reason: 'an existing chat keeps its own agent',
    );
  });

  test('a new chat carries the agent, mode and plan choice', () {
    final input = const AgentChatDelegateDraft()
        .copyWith(
          task: ' Ship it \n',
          title: '  ',
          workspaceId: 'ws-1',
          providerInstanceId: 'claudeAgent',
          model: 'opus',
          runtimeMode: AgentChatRuntimeMode.auto,
          plan: true,
        )
        .toInput('request-1');
    expect(input.toJson(), <String, Object?>{
      'requestId': 'request-1',
      'task': 'Ship it',
      'mode': 'async',
      'target': <String, Object?>{
        'workspace': <String, Object?>{'workspaceId': 'ws-1'},
      },
      'agent': <String, Object?>{
        'providerInstanceId': 'claudeAgent',
        'model': 'opus',
      },
      'runtimeMode': 'auto',
      'interactionMode': 'plan',
    });
  });

  test('an existing chat target sends no agent settings', () {
    final input = const AgentChatDelegateDraft()
        .copyWith(
          targetKind: AgentChatTaskTargetKind.chat,
          task: 'Continue',
          chatId: 'chat-9',
          providerInstanceId: 'codex',
          runtimeMode: AgentChatRuntimeMode.fullAccess,
        )
        .toInput('request-2');
    expect(input.agent, isNull);
    expect(input.runtimeMode, isNull);
    expect(input.target.toJson(), <String, Object?>{
      'chat': <String, Object?>{'chatId': 'chat-9'},
    });
  });

  test('a new workspace names its project, host, mode and setup', () {
    final draft = const AgentChatDelegateDraft().copyWith(
      targetKind: AgentChatTaskTargetKind.newWorkspace,
      task: 'Port the parser',
      projectId: 'project-1',
      hostId: 'ssh-1',
      mode: AgentChatWorkspaceMode.shared,
      setup: AgentChatWorkspaceSetup.deferred,
      branch: ' ',
      workspaceName: ' Parser ',
      providerInstanceId: 'codex',
    );
    expect(draft.toInput('request-3').target.toJson(), <String, Object?>{
      'newWorkspace': <String, Object?>{
        'projectId': 'project-1',
        'hostId': 'ssh-1',
        'mode': 'shared',
        'name': 'Parser',
        'setup': 'deferred',
      },
    });
    expect(
      () => draft.copyWith(projectId: null).toInput('request-4'),
      throwsStateError,
    );
  });

  test('copyWith clears nullable fields only when asked', () {
    const draft = AgentChatDelegateDraft(
      chatId: 'chat-1',
      providerInstanceId: 'codex',
      model: 'gpt-5',
    );
    final kept = draft.copyWith(task: 'x');
    expect(kept.chatId, 'chat-1');
    expect(kept.model, 'gpt-5');
    final cleared = draft.copyWith(model: null, chatId: null);
    expect(cleared.chatId, isNull);
    expect(cleared.model, isNull);
    expect(cleared.providerInstanceId, 'codex');
  });

  test('request ids repeat for an unchanged action and renew on edits', () {
    var next = 0;
    final ids = AgentChatRequestIds(() => 'id-${next++}');
    final draft = const AgentChatDelegateDraft().copyWith(
      task: 'Ship it',
      workspaceId: 'ws-1',
      providerInstanceId: 'codex',
    );
    final first = ids.idFor(draft.fingerprint);
    expect(ids.idFor(draft.fingerprint), first);
    final edited = ids.idFor(draft.copyWith(task: 'Ship it now').fingerprint);
    expect(edited, isNot(first));
    ids.reset();
    expect(ids.idFor(draft.fingerprint), isNot(edited));
  });
}
