import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes derived catalog fields without approval state', () {
    final record = AutomationRecord.fromJson(<String, Object?>{
      'id': 'nightly',
      'slug': 'nightly',
      'name': 'Nightly',
      'promptTemplate': 'Review',
      'schedule': <String, Object?>{
        'recurring': <String, Object?>{
          'cron': '0 9 * * 1-5',
          'timezone': 'UTC',
        },
      },
      'target': <String, Object?>{
        'projectCheckout': <String, Object?>{
          'projectId': 'project-1',
          'hostId': 'local',
          'agentProfileId': 'codex',
        },
      },
      'state': 'active',
      'revision': 4,
      'originWorkspaceId': 'ws-1',
      'association': <String, Object?>{
        'workspaceId': 'ws-1',
        'sectionId': 'section-1',
        'projectId': 'project-1',
        'source': 'origin',
      },
      'targetHostId': 'local',
      'nextRunAt': '2026-10-05T13:00:00Z',
      'lastRun': <String, Object?>{'id': 'run-1', 'status': 'failure'},
      'activeRunCount': 1,
      'readiness': <String, Object?>{
        'ready': false,
        'issues': <Object?>[
          <String, Object?>{
            'code': 'profileCommandMissing',
            'message': 'Agent CLI codex not found.',
            'field': 'target.agentProfileId',
            'severity': 'error',
          },
          <String, Object?>{
            'code': 'hostUnreachable',
            'message': 'The host is offline.',
            'severity': 'warning',
          },
        ],
      },
      'attention': <String, Object?>{
        'code': 'targetRemoved',
        'message': 'Target workspace removed.',
      },
    });

    expect(record.targetType, AutomationTargetType.projectCheckout);
    expect(record.agentProfileId, 'codex');
    expect(record.association?.source, AutomationAssociationSource.origin);
    expect(record.association?.sectionId, 'section-1');
    expect(record.associatedWorkspaceId, 'ws-1');
    expect(record.effectiveProjectId, 'project-1');
    expect(record.nextRunAt, DateTime.parse('2026-10-05T13:00:00Z'));
    expect(record.lastRun?.status, 'failure');
    expect(record.readiness?.errors.single.code, 'profileCommandMissing');
    expect(record.readiness?.warnings.single.code, 'hostUnreachable');
    expect(record.attention?.message, 'Target workspace removed.');
  });

  test('archived definitions are completed and read-only', () {
    final record = AutomationRecord.fromJson(const <String, Object?>{
      'id': 'once',
      'state': 'archived',
    });
    expect(record.isCompleted, isTrue);
    expect(record.isEditable, isFalse);
  });

  test('runs keep old status values and expose recovery separately', () {
    final run = AutomationRunRecord.fromJson(<String, Object?>{
      'id': 'run-2',
      'automationId': 'nightly',
      'number': 2,
      'status': 'dispatched',
      'trigger': 'manual',
      'targetIdentity': <String, Object?>{
        'workspaceId': 'ws-1',
        'tabId': 'tab-1',
      },
      'recovery': <String, Object?>{
        'status': 'retryingWithContext',
        'attempt': 2,
        'maxAttempts': 3,
      },
      'continueFromRunId': 'run-1',
      'lastHeartbeatAt': '2026-10-04T10:00:00Z',
    });
    expect(run.status, 'dispatched');
    expect(run.isActive, isTrue);
    expect(run.recovery.status, AutomationRecoveryStatus.retryingWithContext);
    expect(run.recovery.isActive, isTrue);
    expect(run.workspaceId, 'ws-1');
    expect(run.tabId, 'tab-1');
    expect(run.continueFromRunId, 'run-1');
    expect(run.lastActivityAt, DateTime.parse('2026-10-04T10:00:00Z'));
  });

  test('detail groups attempts per run in launch order', () {
    final detail = AutomationDetail.fromJson(<String, Object?>{
      'automation': <String, Object?>{'id': 'nightly'},
      'attempts': <Object?>[
        <String, Object?>{'id': 'b', 'runId': 'run-1', 'number': 2},
        <String, Object?>{'id': 'a', 'runId': 'run-1', 'number': 1},
        <String, Object?>{'id': 'c', 'runId': 'run-2', 'number': 1},
      ],
    });
    expect(detail.attemptsFor('run-1').map((item) => item.id), ['a', 'b']);
  });
}
