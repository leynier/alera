import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decodes policy fields and identifies recurring existing-tab records',
    () {
      final record = AutomationRecord.fromJson(<String, Object?>{
        'id': 'automation-1',
        'slug': 'nightly',
        'name': 'Nightly',
        'description': 'Run the nightly task',
        'promptTemplate': 'Review {{project.name}}',
        'schedule': <String, Object?>{'recurring': '0 0 * * *'},
        'target': <String, Object?>{'existingTab': 'tab-1'},
        'state': 'active',
        'revision': 4,
        'approvedRevision': 4,
        'updatedAt': '2026-08-03T12:00:00Z',
        'tagIds': <Object?>['tag-a', '', 7],
        'setupPolicy': 'parallel',
        'cleanupPolicy': 'onSuccess',
        'overlapPolicy': 'queue',
        'queueCap': 10,
        'inactivityTimeoutSeconds': 300,
        'heartbeatIntervalSeconds': 30,
        'misfirePolicy': 'runLatestOnce',
        'retryMaxAttempts': 3,
        'retryBackoffSeconds': 20,
        'circuitFailureThreshold': 2,
        'circuitOpenSeconds': 600,
        'precheck': <String, Object?>{'command': 'test -f alera.toml'},
        'notifyOnSuccess': true,
      });

      expect(record.id, 'automation-1');
      expect(record.isApproved, isTrue);
      expect(record.scheduleKind, 'Recurring');
      expect(record.targetKind, 'Existing tab');
      expect(record.tagIds, <String>['tag-a']);
      expect(record.overlapPolicy, 'queue');
      expect(record.misfirePolicy, 'runLatestOnce');
      expect(record.notifyOnSuccess, isTrue);
      expect(record.updatedAt, DateTime.parse('2026-08-03T12:00:00Z'));
    },
  );

  test('applies safe defaults for incomplete persisted records', () {
    final record = AutomationRecord.fromJson(const <String, Object?>{});

    expect(record.state, 'draft');
    expect(record.setupPolicy, 'wait');
    expect(record.overlapPolicy, 'skip');
    expect(record.misfirePolicy, 'skip');
    expect(record.queueCap, 10);
    expect(record.inactivityTimeoutSeconds, 7200);
    expect(record.heartbeatIntervalSeconds, 60);
    expect(record.retryMaxAttempts, 3);
    expect(record.isApproved, isFalse);
    expect(record.scheduleKind, 'One-time');
    expect(record.targetKind, 'Managed workspace');
  });

  test('decodes run and detail history without requiring optional fields', () {
    final detail = AutomationDetail.fromJson(<String, Object?>{
      'automation': <String, Object?>{
        'id': 'automation-2',
        'schedule': <String, Object?>{'oneTime': '2026-08-03T12:00:00Z'},
        'target': <String, Object?>{'freshTab': true},
      },
      'runs': <Object?>[
        <String, Object?>{
          'id': 'run-1',
          'automationId': 'automation-2',
          'number': 1,
          'status': 'blocked',
          'trigger': 'manual',
          'summary': 'Waiting for approval',
          'targetIdentity': <String, Object?>{'tabId': 'tab-1'},
        },
      ],
      'audit': <Object?>[
        <String, Object?>{'action': 'created'},
      ],
      'occurrences': <Object?>[
        <String, Object?>{'meaning': 'next'},
      ],
      'effectivePolicies': <String, Object?>{'mayExecute': false},
    });

    expect(detail.automation.targetKind, 'Fresh tab');
    expect(detail.runs.single.status, 'blocked');
    expect(detail.runs.single.finishedAt, isNull);
    expect(detail.audit.single['action'], 'created');
    expect(detail.occurrences.single['meaning'], 'next');
    expect(detail.effectivePolicies['mayExecute'], isFalse);
  });
}
