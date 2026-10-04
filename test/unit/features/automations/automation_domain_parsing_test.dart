import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_timezones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worktree definitions expose their source workspace and author', () {
    final record = AutomationRecord.fromJson(<String, Object?>{
      'schedule': <String, Object?>{
        'recurring': <String, Object?>{'cron': '0 9 * * *', 'timezone': 'UTC'},
      },
      'target': <String, Object?>{
        'managedWorkspace': <String, Object?>{'sourceWorkspaceId': 'ws-src'},
      },
      'precheck': <String, Object?>{'command': 'true'},
      'createdBy': <String, Object?>{
        'kind': 'managedAgent',
        'label': 'Codex Daily',
      },
    });
    expect(record.isRecurring, isTrue);
    expect(record.scheduleDetails['timezone'], 'UTC');
    expect(record.targetWorkspaceId, 'ws-src');
    expect(record.associatedWorkspaceId, 'ws-src');
    expect(record.precheck, <String, Object?>{'command': 'true'});
    expect(record.createdByAgent, isTrue);
    expect(record.createdByLabel, 'Codex Daily');
  });

  test('a definition without a target or schedule degrades safely', () {
    final record = AutomationRecord.fromJson(const <String, Object?>{});
    expect(record.isRecurring, isFalse);
    expect(record.scheduleDetails, isEmpty);
    expect(record.targetType, isNull);
    expect(record.targetDetails, isEmpty);
    expect(record.createdByAgent, isFalse);
    expect(record.createdByLabel, isNull);
  });

  test('numeric and list fields accept what the runtime may send', () {
    expect(automationJsonOptionalInt(null), isNull);
    expect(automationJsonOptionalInt(4), 4);
    expect(automationJsonOptionalInt(4.9), 4);
    expect(automationJsonOptionalInt('12'), 12);
    expect(automationJsonOptionalInt('soon'), isNull);
    expect(automationJsonInt(2.5), 2);
    expect(automationJsonStringList('tag'), isEmpty);
    expect(automationJsonStringList(<Object?>['a', ' ', 3]), <String>['a']);
  });

  test('readiness without a verdict is decided by its errors', () {
    final readiness = AutomationReadiness.fromJson(<String, Object?>{
      'issues': <Object?>[
        <String, Object?>{
          'code': 'targetMissing',
          'message': 'Choose a target.',
          'field': 'target',
        },
        <String, Object?>{
          'code': 'hostUnreachable',
          'message': 'Host offline.',
          'severity': 'warning',
        },
      ],
    });
    expect(readiness.ready, isFalse);
    expect(readiness.issuesFor('target').single.code, 'targetMissing');
    expect(readiness.issuesFor('schedule'), isEmpty);
    final onlyWarnings = AutomationReadiness.fromJson(<String, Object?>{
      'issues': <Object?>[
        <String, Object?>{'message': 'Slow host.', 'severity': 'warning'},
      ],
    });
    expect(onlyWarnings.ready, isTrue);
  });

  test('limits follow the runtime, including the heartbeat ceiling', () {
    expect(
      AutomationNumericField.heartbeatIntervalSeconds.validate(
        '601',
        inactivityTimeoutSeconds: 600,
      ),
      'Use 1 to 600 seconds, no longer than the inactivity timeout.',
    );
    expect(
      AutomationNumericField.heartbeatIntervalSeconds.validate('86400'),
      isNull,
    );
    expect(
      AutomationNumericField.maxScheduledRuns.validate('0'),
      'Use at least 1.',
    );
    expect(AutomationNumericField.maxScheduledRuns.validate(''), isNull);
    expect(AutomationNumericField.queueCap.validate(''), 'Enter a number.');
    expect(
      AutomationNumericField.queueCap.validate('2.5'),
      'Enter a whole number.',
    );
    expect(automationPolicyLabel('onSuccess'), 'Clean Up On Success');
    expect(automationPolicyLabel('somethingNew'), 'somethingNew');
  });

  test('scopes compare by kind and id', () {
    const a = AutomationScope(kind: .workspace, id: 'ws-1');
    const b = AutomationScope(kind: .workspace, id: 'ws-1');
    const c = AutomationScope(kind: .section, id: 'ws-1');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
    expect(<AutomationScope>{a, c}..add(b), hasLength(2));
  });

  test('a time zone outside the common list is kept first', () {
    expect(automationTimezoneChoices('Asia/Kathmandu').first, 'Asia/Kathmandu');
    expect(automationTimezoneChoices('UTC'), automationCommonTimezones);
    expect(automationTimezoneChoices(null), automationCommonTimezones);
  });
}
