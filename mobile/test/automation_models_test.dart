import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes automation details and preserves effective policies', () {
    final detail = MobileAutomationDetail.fromJson(<String, Object?>{
      'automation': <String, Object?>{
        'id': 'automation-1',
        'name': 'Nightly',
        'slug': 'nightly',
        'state': 'active',
        'revision': 3,
        'approvedRevision': 3,
        'description': 'Review the project',
        'promptTemplate': 'Review {{project.name}}',
        'schedule': <String, Object?>{'recurring': '0 0 * * *'},
        'target': <String, Object?>{'existingTab': 'tab-1'},
        'projectId': 'project-1',
        'tagIds': <Object?>['tag-a', 'tag-b'],
        'heartbeatIntervalSeconds': 45,
      },
      'runs': <Object?>[
        <String, Object?>{'status': 'success', 'number': 1},
      ],
      'audit': <Object?>[
        <String, Object?>{'action': 'approved'},
      ],
      'occurrences': <Object?>[
        <String, Object?>{'meaning': 'next'},
      ],
      'effectivePolicies': <String, Object?>{
        'mayExecute': true,
        'repoDeclared': true,
      },
    });

    expect(detail.automation.isApproved, isTrue);
    expect(detail.automation.projectId, 'project-1');
    expect(detail.automation.tagIds, <String>['tag-a', 'tag-b']);
    expect(detail.automation.heartbeatIntervalSeconds, 45);
    expect(detail.runs.single['status'], 'success');
    expect(detail.audit.single['action'], 'approved');
    expect(detail.effectivePolicies['mayExecute'], isTrue);
  });

  test('uses safe defaults for missing heartbeat and nullable approval', () {
    final automation = MobileAutomation.fromJson(const <String, Object?>{
      'id': 'automation-2',
      'revision': 1,
      'approvedRevision': null,
      'projectId': '',
    });

    expect(automation.approvedRevision, isNull);
    expect(automation.projectId, isNull);
    expect(automation.heartbeatIntervalSeconds, 60);
    expect(automation.isApproved, isFalse);
  });
}
