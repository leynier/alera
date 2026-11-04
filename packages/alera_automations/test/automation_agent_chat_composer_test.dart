import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 11, 4, 9, 30, 15, 250);

AutomationDraft _agentChatDraft() => AutomationTargetChoice.agentChat.applyTo(
  const AutomationDraft(promptTemplate: 'Check the deploy.'),
);

void main() {
  group('agent chat target', () {
    test('is offered only with the runtime capability', () {
      expect(
        AutomationTargetChoice.offered(agentChat: false),
        isNot(contains(AutomationTargetChoice.agentChat)),
      );
      expect(
        AutomationTargetChoice.offered(agentChat: true),
        contains(AutomationTargetChoice.agentChat),
      );
    });

    test('starts with the most permissive mode ceiling', () {
      final draft = _agentChatDraft();
      expect(draft.targetType, AutomationTargetType.agentChat);
      expect(
        AutomationTargetChoice.of(draft),
        AutomationTargetChoice.agentChat,
      );
      expect(draft.agentChat.runtimeModeCeiling, 'full-access');
      expect(
        automationAgentChatRuntimeModes.last,
        automationDefaultRuntimeModeCeiling,
      );
      expect(draft.destinationError, 'Complete the destination.');
      expect(draft.whereError, isNotNull);
    });

    test('a new chat each run saves its agent and ceiling', () {
      final draft = _agentChatDraft()
          .withAgentChatWorkspace('ws-1')
          .let(
            (draft) => draft.withAgentChat(
              draft.agentChat
                  .withAgent(
                    provider: 'codex',
                    providerInstanceId: 'codex-work',
                    model: 'gpt-5.5',
                  )
                  .withReasoningEffort('high')
                  .withRuntimeModeCeiling('auto'),
            ),
          );
      expect(draft.destinationError, isNull);
      expect(draft.whereError, isNull);
      // The runtime's `AutomationTarget::AgentChat` reads these camelCase
      // fields (`automation_target.rs`).
      expect(draft.toDefinition()['target'], <String, Object?>{
        'agentChat': <String, Object?>{
          'workspaceId': 'ws-1',
          'runtimeModeCeiling': 'auto',
          'provider': 'codex',
          'providerInstanceId': 'codex-work',
          'model': 'gpt-5.5',
          'reasoningEffort': 'high',
        },
      });
    });

    test('binding to a chat drops the agent; a new chat keeps it', () {
      final withAgent = _agentChatDraft()
          .withAgentChatWorkspace('ws-1')
          .let(
            (draft) => draft.withAgentChat(
              draft.agentChat.withAgent(
                provider: 'claudeAgent',
                providerInstanceId: 'claude',
              ),
            ),
          );
      final bound = withAgent.withAgentChat(
        withAgent.agentChat.boundTo('chat-9'),
      );
      expect(bound.targetJson, <String, Object?>{
        'agentChat': <String, Object?>{
          'chatId': 'chat-9',
          'workspaceId': 'ws-1',
          'runtimeModeCeiling': 'full-access',
        },
      });
      expect(bound.destinationError, isNull);
      final unbound = bound.withAgentChat(withAgent.agentChat.newChat());
      expect(unbound.agentChat.chatId, isNull);
      expect(unbound.agentChat.provider, 'claudeAgent');
    });

    test('a picked agent keeps an offered ceiling, else its most access', () {
      const start = AutomationAgentChatTarget(
        workspaceId: 'ws',
        runtimeModeCeiling: 'full-access',
      );
      final limited = start.pickAgent(
        provider: 'gemini',
        providerInstanceId: 'gemini',
        modes: <String>['approval-required', 'auto'],
      );
      expect(limited.runtimeModeCeiling, 'auto');
      final lowered = start
          .withRuntimeModeCeiling('approval-required')
          .pickAgent(
            provider: 'codex',
            providerInstanceId: 'codex',
            modes: automationAgentChatRuntimeModes,
          );
      expect(lowered.runtimeModeCeiling, 'approval-required');
      expect(
        automationMostPermissiveMode(<String>['auto', 'auto-accept-edits']),
        'auto',
      );
      expect(automationMostPermissiveMode(<String>['unknown']), isNull);
    });

    test('another workspace drops the chat but keeps the agent', () {
      final draft = _agentChatDraft()
          .withAgentChatWorkspace('ws-1')
          .let(
            (draft) => draft.withAgentChat(draft.agentChat.boundTo('chat-1')),
          )
          .withAgentChatWorkspace('ws-2');
      expect(draft.agentChat.workspaceId, 'ws-2');
      expect(draft.agentChat.chatId, isNull);
      expect(draft.agentChat.runtimeModeCeiling, 'full-access');
    });

    test('a stored target round-trips, unknown fields included', () {
      final record = AutomationRecord.fromJson(<String, Object?>{
        'id': 'a',
        'slug': 'check-a',
        'name': 'Check',
        'promptTemplate': 'Check.',
        'state': 'active',
        'revision': 1,
        'schedule': <String, Object?>{
          'recurring': <String, Object?>{'cron': '0 9 * * 1-5'},
        },
        'target': <String, Object?>{
          'agentChat': <String, Object?>{
            'workspaceId': 'ws',
            'provider': 'codex',
            'runtimeModeCeiling': 'auto',
            'futureField': 1,
          },
        },
      });
      final draft = AutomationDraft.fromRecord(record);
      expect(draft.agentChat.provider, 'codex');
      final edited = draft.withAgentChat(
        draft.agentChat.withRuntimeModeCeiling('approval-required'),
      );
      expect(edited.targetJson, <String, Object?>{
        'agentChat': <String, Object?>{
          'futureField': 1,
          'workspaceId': 'ws',
          'runtimeModeCeiling': 'approval-required',
          'provider': 'codex',
        },
      });
      expect(edited.definitionKey, isNot(draft.definitionKey));
    });
  });

  group('interval schedule', () {
    test('is offered only with the runtime capability', () {
      expect(
        AutomationScheduleKind.offered(interval: false),
        isNot(contains(AutomationScheduleKind.interval)),
      );
      expect(
        AutomationScheduleKind.offered(
          interval: false,
          current: AutomationScheduleKind.interval,
        ),
        contains(AutomationScheduleKind.interval),
      );
      expect(
        AutomationScheduleKind.offered(interval: true),
        contains(AutomationScheduleKind.interval),
      );
    });

    test('a new interval counts from now', () {
      final preset = AutomationSchedulePreset.initial.withKind(
        AutomationScheduleKind.interval,
        now: _now,
      );
      expect(preset.intervalAnchor, DateTime.utc(2026, 11, 4, 9, 30, 15));
      expect(preset.toSchedule(timezone: 'Europe/Madrid'), <String, Object?>{
        'interval': <String, Object?>{
          'everySeconds': 3600,
          'anchor': '2026-11-04T09:30:15.000Z',
        },
      });
      expect(preset.intervalUnit, AutomationIntervalUnit.hours);
      expect(preset.intervalCount, 1);
    });

    test('editing keeps the stored anchor until the interval changes', () {
      final stored = AutomationSchedulePreset.fromSchedule(<String, Object?>{
        'interval': <String, Object?>{
          'everySeconds': 2 * 86400,
          'anchor': '2026-11-01T08:00:00Z',
        },
      });
      expect(stored.intervalUnit, AutomationIntervalUnit.days);
      expect(stored.intervalCount, 2);
      final same = stored.withInterval(48, .hours, now: _now);
      expect(same.intervalAnchor, DateTime.utc(2026, 11, 1, 8));
      final changed = stored.withInterval(3, .days, now: _now);
      expect(changed.everySeconds, 3 * 86400);
      expect(changed.intervalAnchor, DateTime.utc(2026, 11, 4, 9, 30, 15));
      expect(changed.describe(), 'Every 3 days');
      // A preset read back from what it saves is the same schedule.
      final reread = AutomationSchedulePreset.fromSchedule(
        changed.toSchedule(),
      );
      expect(reread.everySeconds, changed.everySeconds);
      expect(reread.intervalAnchor, changed.intervalAnchor);
    });

    test('a unit change keeps the count', () {
      final preset = AutomationSchedulePreset.initial
          .withKind(.interval, now: _now)
          .withInterval(15, .minutes, now: _now);
      expect(preset.everySeconds, 900);
      expect(preset.withInterval(15, .hours).everySeconds, 15 * 3600);
    });

    test('validates the runtime bounds', () {
      final preset = AutomationSchedulePreset.initial.withKind(
        .interval,
        now: _now,
      );
      expect(preset.withInterval(0, .minutes).localError, isNotNull);
      expect(preset.withInterval(1, .minutes).localError, isNull);
      expect(preset.copyWith(everySeconds: 59).localError, isNotNull);
      expect(preset.withInterval(366, .days).localError, isNull);
      expect(preset.withInterval(367, .days).localError, isNotNull);
    });

    test('an interval has no cron limits or time zone', () {
      final draft =
          const AutomationDraft(
            promptTemplate: 'Check.',
            timezone: 'Europe/Madrid',
            startAt: '2026-11-05T00:00:00Z',
          ).let(
            (draft) => draft.copyWith(
              schedule: draft.schedule.withKind(.interval, now: _now),
            ),
          );
      expect(draft.offersScheduleLimits, isFalse);
      expect(draft.toDefinition()['schedule'], <String, Object?>{
        'interval': <String, Object?>{
          'everySeconds': 3600,
          'anchor': '2026-11-04T09:30:15.000Z',
        },
      });
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T value) apply) => apply(this);
}
