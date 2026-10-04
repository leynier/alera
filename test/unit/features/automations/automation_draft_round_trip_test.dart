import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:flutter_test/flutter_test.dart';

AutomationRecord _checkoutRecord() =>
    AutomationRecord.fromJson(<String, Object?>{
      'id': 'nightly',
      'slug': 'nightly',
      'name': 'Nightly',
      'description': 'Checks the build',
      'promptTemplate': 'Review',
      'tagIds': <Object?>['tag-1'],
      'schedule': <String, Object?>{
        'recurring': <String, Object?>{
          'cron': '30 6 * * 1,3',
          'timezone': 'Europe/Madrid',
          'startAt': '2026-10-01T00:00:00Z',
          'endAt': '2026-12-01T00:00:00Z',
          'maxScheduledRuns': 12,
        },
      },
      'target': <String, Object?>{
        'projectCheckout': <String, Object?>{
          'projectId': 'project-1',
          'hostId': 'ssh-1',
          'nameTemplate': 'nightly-{{run.number}}',
          'agentProfileId': 'codex',
        },
      },
      'originWorkspaceId': 'ws-9',
      'state': 'active',
      'revision': 4,
      'queueCap': 4,
      'inactivityTimeoutSeconds': 3600,
      'heartbeatIntervalSeconds': 30,
      'misfireGraceSeconds': 0,
      'misfirePolicy': 'queue',
      'overlapPolicy': 'forceParallel',
      'setupPolicy': 'parallel',
      'cleanupPolicy': 'onSuccess',
      'retryMaxAttempts': 2,
      'retryBackoffSeconds': 90,
      'circuitFailureThreshold': 5,
      'circuitOpenSeconds': 1200,
      'precheck': <String, Object?>{
        'command': 'test -f ready',
        'timeoutSeconds': 30,
      },
      'notifyOnSuccess': true,
    });

void main() {
  test('editing a persisted definition keeps every setting it had', () {
    final draft = AutomationDraft.fromRecord(_checkoutRecord());
    expect(draft.targetType, AutomationTargetType.projectCheckout);
    expect(draft.field(.projectId), 'project-1');
    expect(draft.field(.hostId), 'ssh-1');
    expect(draft.field(.agentProfileId), 'codex');
    expect(draft.whereError, isNull);
    expect(draft.schedule.kind, AutomationScheduleKind.weekly);
    expect(draft.timezone, 'Europe/Madrid');
    expect(draft.number(.maxScheduledRuns), '12');
    expect(draft.number(.precheckTimeoutSeconds), '30');

    final definition = draft.toDefinition();
    expect(definition['slug'], 'nightly');
    expect(definition['projectId'], 'project-1');
    expect(definition['originWorkspaceId'], 'ws-9');
    expect(definition['precheck'], <String, Object?>{
      'command': 'test -f ready',
      'timeoutSeconds': 30,
    });
    expect(definition['target'], <String, Object?>{
      'projectCheckout': <String, Object?>{
        'projectId': 'project-1',
        'hostId': 'ssh-1',
        'nameTemplate': 'nightly-{{run.number}}',
        'agentProfileId': 'codex',
      },
    });
    expect((definition['schedule']! as Map)['recurring'], <String, Object?>{
      'cron': '30 6 * * 1,3',
      'timezone': 'Europe/Madrid',
      'startAt': '2026-10-01T00:00:00Z',
      'endAt': '2026-12-01T00:00:00Z',
      'maxScheduledRuns': 12,
    });
    for (final (field, value) in <(AutomationNumericField, int)>[
      (.queueCap, 4),
      (.inactivityTimeoutSeconds, 3600),
      (.heartbeatIntervalSeconds, 30),
      (.misfireGraceSeconds, 0),
      (.retryMaxAttempts, 2),
      (.retryBackoffSeconds, 90),
      (.circuitFailureThreshold, 5),
      (.circuitOpenSeconds, 1200),
    ]) {
      expect(definition[field.key], value, reason: field.key);
    }
    expect(definition['misfirePolicy'], 'queue');
    expect(definition['overlapPolicy'], 'forceParallel');
    expect(definition['setupPolicy'], 'parallel');
    expect(definition['cleanupPolicy'], 'onSuccess');
    expect(definition['notifyOnSuccess'], isTrue);
  });

  test('a clone is a new definition with the same target and settings', () {
    final clone = AutomationDraft.fromRecord(_checkoutRecord()).cloned();
    final definition = clone.toDefinition();
    expect(definition.containsKey('slug'), isFalse);
    expect(definition['name'], 'Nightly Copy');
    expect(definition['target'], isNotNull);
    expect(definition['originWorkspaceId'], 'ws-9');
    expect(definition['precheck'], isNotNull);
  });

  test('each target type sends only its own fields', () {
    final worktree = const AutomationDraft()
        .withTargetType(AutomationTargetType.managedWorkspace)
        .withTargetField(.workspaceId, ' ws-1 ')
        .withTargetField(.sourceBranch, 'main')
        .withTargetField(.agentProfileId, 'codex');
    expect(worktree.targetJson, <String, Object?>{
      'managedWorkspace': <String, Object?>{
        'sourceWorkspaceId': 'ws-1',
        'sourceBranch': 'main',
        'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
        'agentProfileId': 'codex',
      },
    });
    final conversation = const AutomationDraft()
        .withTargetType(AutomationTargetType.existingTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.tabId, 'tab-1');
    expect(conversation.requiredTargetFields, <AutomationDraftField>[
      .workspaceId,
      .tabId,
      .conversationId,
    ]);
    expect(conversation.whereError, isNotNull);
    final complete = conversation.withTargetField(.conversationId, 'c-1');
    expect(complete.whereError, isNull);
    expect(complete.targetJson, <String, Object?>{
      'existingTab': <String, Object?>{
        'workspaceId': 'ws-1',
        'tabId': 'tab-1',
        'conversationId': 'c-1',
      },
    });
    expect(complete.toDefinition().containsKey('projectId'), isFalse);
  });

  test('clearing a field removes it instead of sending blanks', () {
    final draft = const AutomationDraft()
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.workspaceId, '   ');
    expect(draft.field(.workspaceId), isNull);
    expect(
      (draft.targetJson!['freshTab']! as Map).containsKey('workspaceId'),
      isFalse,
    );
  });

  test('the name falls back to the prompt, shortened, or a plain label', () {
    expect(const AutomationDraft().effectiveName, 'Automation');
    expect(
      const AutomationDraft(promptTemplate: 'Short task\nmore').effectiveName,
      'Short task',
    );
    final long = 'x' * 60;
    expect(
      AutomationDraft(promptTemplate: long).effectiveName,
      '${'x' * 48}...',
    );
    expect(
      const AutomationDraft(name: ' Named ', promptTemplate: 'x').effectiveName,
      'Named',
    );
  });
}
