import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:flutter_test/flutter_test.dart';

AutomationRunRecord _run(
  String status, {
  Map<String, Object?>? recovery,
  String id = 'run',
}) => AutomationRunRecord.fromJson(<String, Object?>{
  'id': id,
  'status': status,
  'recovery': ?recovery,
});

void main() {
  test('final statuses never read as in progress', () {
    for (final status in automationFinalRunStatuses) {
      expect(
        automationRunStatusLabel(_run(status)).inProgress,
        isFalse,
        reason: status,
      );
    }
    expect(
      automationRunStatusLabel(_run('precheckSkipped')).label,
      'Skipped: Precheck',
    );
    expect(automationRunStatusLabel(_run('timeout')).label, 'Timed Out');
  });

  test('recovery phases relabel a running run without new statuses', () {
    expect(
      automationRunStatusLabel(
        _run('dispatched', recovery: {'status': 'reconnecting'}),
      ).label,
      'Reconnecting',
    );
    expect(
      automationRunStatusLabel(
        _run(
          'dispatched',
          recovery: {'status': 'reconnecting', 'code': 'ownerRunning'},
        ),
      ).label,
      'Waiting For Previous Owner',
    );
    expect(
      automationRunStatusLabel(
        _run('dispatched', recovery: {'status': 'resuming'}),
      ).label,
      'Resuming Conversation',
    );
    final last = automationRunStatusLabel(
      _run(
        'pending',
        recovery: {
          'status': 'retryingWithContext',
          'attempt': 3,
          'maxAttempts': 3,
        },
      ),
    );
    expect(last.label, 'Retrying With Context · Attempt 3 Of 3');
    expect(last.tone, AutomationTone.warning);
  });

  test('consecutive missed occurrences collapse into one entry', () {
    final history = automationRunHistory(<AutomationRunRecord>[
      _run('success', id: 'a'),
      _run('misfireSkipped', id: 'b'),
      _run('misfireSkipped', id: 'c'),
      _run('misfireSkipped', id: 'd'),
      _run('failure', id: 'e'),
    ]);
    expect(history, hasLength(3));
    expect(
      (history[1] as AutomationRunHistoryMissed).runs.map((run) => run.id),
      <String>['b', 'c', 'd'],
    );
  });
}
