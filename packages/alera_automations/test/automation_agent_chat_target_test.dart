import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

final class _Names implements AutomationNameLookup {
  @override
  String hostName(String? id) => 'host';

  @override
  String profileName(String? id) => 'profile';

  @override
  String projectName(String? id) => 'project';

  @override
  String workspaceName(String? id) => 'Workspace $id';
}

AutomationRecord _record({String? chatId}) =>
    AutomationRecord.fromJson(<String, Object?>{
      'id': 'a',
      'slug': 'check-a',
      'name': 'Check the deploy',
      'promptTemplate': 'Check the deploy.',
      'state': 'active',
      'revision': 1,
      'schedule': <String, Object?>{
        'interval': <String, Object?>{
          'everySeconds': 900,
          'anchor': '2026-11-03T10:00:00Z',
        },
      },
      'target': <String, Object?>{
        'agentChat': <String, Object?>{
          'chatId': ?chatId,
          'workspaceId': 'ws',
          'runtimeModeCeiling': 'auto',
          'provider': 'codex',
        },
      },
    });

void main() {
  test('capability names match the runtime', () {
    expect(automationAgentChatTargetCapability, 'automationAgentChatTargetV1');
  });

  test('an agent chat target reads, summarizes and round-trips', () {
    final record = _record(chatId: 'chat-1');
    expect(record.targetType, AutomationTargetType.agentChat);
    expect(record.targetChatId, 'chat-1');
    expect(record.targetWorkspaceId, 'ws');
    expect(record.isRecurring, isTrue);
    expect(record.intervalSeconds, 900);
    expect(AutomationTargetType.agentChat.isComposable, isFalse);
    expect(AutomationTargetType.agentChat.usesAgentProfile, isFalse);
    expect(AutomationTargetType.agentChat.createsWorkspace, isFalse);

    final draft = AutomationDraft.fromRecord(record);
    expect(draft.whereError, isNull);
    expect(AutomationTargetChoice.of(draft), isNull);
    expect(applicableReusePolicies(draft.targetType), <AutomationReusePolicy>[
      AutomationReusePolicy.newEachRun,
    ]);
    final definition = draft.toDefinition();
    expect(definition['target'], <String, Object?>{
      'agentChat': <String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws',
        'runtimeModeCeiling': 'auto',
        'provider': 'codex',
      },
    });
    expect(definition['schedule'], <String, Object?>{
      'interval': <String, Object?>{
        'everySeconds': 900,
        'anchor': '2026-11-03T10:00:00.000Z',
      },
    });
    expect(
      automationTargetSummary(draft, _Names()),
      'Posts into a chat in Workspace ws',
    );
    expect(
      automationTargetSummary(AutomationDraft.fromRecord(_record()), _Names()),
      'New chat in Workspace ws for each run',
    );
  });

  test('choosing another target drops the agent chat details', () {
    final draft = AutomationDraft.fromRecord(_record(chatId: 'chat-1'))
        .withTargetType(AutomationTargetType.freshTab);
    expect(draft.agentChatTarget, isEmpty);
    expect(draft.targetJson, <String, Object?>{
      'freshTab': <String, Object?>{},
    });
  });

  test('interval schedules describe themselves and stay out of the picker', () {
    final preset = AutomationSchedulePreset.fromSchedule(_record().schedule);
    expect(preset.kind, AutomationScheduleKind.interval);
    expect(preset.describe(timezone: 'UTC'), 'Every 15 minutes');
    expect(preset.copyWith(everySeconds: 30).localError, isNotNull);
    expect(AutomationScheduleKind.interval.isComposable, isFalse);
    expect(automationIntervalLabel(3600), 'Every hour');
    expect(automationIntervalLabel(7200), 'Every 2 hours');
    expect(automationIntervalLabel(90), 'Every 90 seconds');
    expect(
      automationScheduleDescription(_record().schedule),
      'Every 15 minutes',
    );
  });

  test('a run that posted into a chat names it', () {
    final run = AutomationRunRecord.fromJson(<String, Object?>{
      'id': 'run',
      'automationId': 'a',
      'number': 1,
      'status': 'dispatched',
      'trigger': 'scheduled',
      'chatId': 'chat-1',
      'workspaceId': 'ws',
    });
    expect(run.chatId, 'chat-1');
    expect(run.isAgentChatRun, isTrue);
  });
}
