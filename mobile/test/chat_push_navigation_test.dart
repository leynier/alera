import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/push_notifications/presentation/push_intent_router.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chat Attention Round Trips Runtime And Chat Identity', () {
    final intent = PushNavigationIntent.fromData(<String, Object?>{
      'accountId': 'account',
      'runtimeId': 'runtime',
      'kind': 'agentChat',
      'eventType': 'grouped',
      'category': 'attention',
      'workspaceId': 'workspace',
      'tabId': 'tab',
      'chatId': 'chat',
    });
    expect(intent.eventKind, PushEventKind.agentChat);
    expect(intent.shouldOpenAgentChat, isTrue);
    expect(intent.shouldOpenTerminal, isFalse);
    expect(activitySectionForPush(intent), isNull);
    final restored = PushNavigationIntent.fromData(intent.toJson());
    expect(restored.runtimeId, 'runtime');
    expect(restored.accountId, 'account');
    expect(restored.chatId, 'chat');
    expect(restored.tabId, 'tab');
  });

  test(
    'Chat Tap Matches Chat Identity And Workspace Instead Of A Reused Tab',
    () {
      const intent = PushNavigationIntent(
        runtimeId: 'runtime',
        eventKind: PushEventKind.agentChat,
        workspaceId: 'workspace',
        tabId: 'tab',
        chatId: 'chat',
      );
      final tabs = <WorkspaceTabSummary>[
        _tab('tab', 'terminal'),
        _tab('tab', 'agentChat', chatId: 'other-chat'),
        _tab(
          'other-workspace',
          'agentChat',
          chatId: 'chat',
          workspaceId: 'other',
        ),
        _tab('reopened-tab', 'agentChat', chatId: 'chat'),
      ];
      expect(tabForPushIntent(intent, tabs)?.id, 'reopened-tab');
      expect(tabForPushIntent(intent, tabs.take(3)), isNull);
    },
  );

  test('Task Attention Opens Activity Even When Its Child Was Deleted', () {
    final intent = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime',
      'category': 'attention',
      'eventType': 'chat_task_attention',
      'taskId': 'task',
      'chatId': null,
    });
    expect(intent.eventKind, PushEventKind.chatTask);
    expect(intent.taskId, 'task');
    expect(intent.shouldOpenTerminal, isFalse);
    expect(activitySectionForPush(intent), ActivitySection.chatTasks);
    expect(PushNavigationIntent.fromData(intent.toJson()).taskId, 'task');
  });

  test('Archived Chat Without A Live Tab Never Falls Back To Another Chat', () {
    const intent = PushNavigationIntent(
      runtimeId: 'paired-hub',
      eventKind: PushEventKind.agentChat,
      workspaceId: 'remote-workspace',
      tabId: 'removed-remote-tab',
      chatId: 'archived-remote-chat',
    );
    expect(
      tabForPushIntent(intent, <WorkspaceTabSummary>[
        _tab('removed-remote-tab', 'terminal', workspaceId: 'remote-workspace'),
        _tab(
          'another-chat',
          'agentChat',
          chatId: 'another-chat',
          workspaceId: 'remote-workspace',
        ),
      ]),
      isNull,
    );
    expect(intent.shouldOpenAgentChat, isTrue);
    expect(intent.shouldOpenTerminal, isFalse);
  });

  test('Legacy Terminal Category Still Resolves With Unknown Payload Kind', () {
    final intent = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime',
      'kind': 'agentStatus',
      'category': 'attention',
      'workspaceId': 'workspace',
      'tabId': 'tab',
    });
    expect(intent.eventKind, PushEventKind.attention);
    expect(
      tabForPushIntent(intent, <WorkspaceTabSummary>[
        _tab('tab', 'terminal'),
      ])?.id,
      'tab',
    );
    expect(
      tabForPushIntent(intent, <WorkspaceTabSummary>[
        _tab('tab', 'agentChat', chatId: 'chat'),
      ]),
      isNull,
    );
  });
}

WorkspaceTabSummary _tab(
  String id,
  String kind, {
  String? chatId,
  String workspaceId = 'workspace',
}) => WorkspaceTabSummary(
  id: id,
  workspaceId: workspaceId,
  kind: kind,
  title: 'Tab',
  payload: <String, Object?>{'chatId': ?chatId},
);
