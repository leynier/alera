import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:flutter_test/flutter_test.dart';

AutomationRunRecord _run(Map<String, Object?> json) =>
    AutomationRunRecord.fromJson(json);

AutomationRecord _automation(String state) =>
    AutomationRecord.fromJson(<String, Object?>{'state': state});

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);

  test('every definition state has a readable label', () {
    expect(automationStateLabel(_automation('active')).label, 'Active');
    expect(automationStateLabel(_automation('paused')).label, 'Paused');
    expect(
      automationStateLabel(_automation('blocked')).label,
      'Needs Attention',
    );
    expect(automationStateLabel(_automation('archived')).label, 'Completed');
    expect(automationStateLabel(_automation('trashed')).label, 'Trash');
    expect(automationStateLabel(_automation('draft')).label, 'Draft');
  });

  test('a queued run waiting to retry says when it tries again', () {
    final retrying = _run(<String, Object?>{
      'status': 'pending',
      'retryAfter': now.add(const Duration(minutes: 2)).toIso8601String(),
    });
    expect(
      automationRunStatusLabel(retrying, now: now).label,
      'Next Attempt In 2m',
    );
    final due = _run(<String, Object?>{
      'status': 'pending',
      'retryAfter': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    });
    expect(automationRunStatusLabel(due, now: now).label, 'Queued');
  });

  test('cancelling and unknown runs are never shown as running', () {
    final cancelling = automationRunStatusLabel(
      _run(<String, Object?>{
        'status': 'dispatched',
        'cancelRequestedAt': now.toIso8601String(),
      }),
    );
    expect(cancelling.label, 'Cancelling');
    expect(cancelling.tone, AutomationTone.neutral);
    expect(
      automationRunStatusLabel(_run(<String, Object?>{'status': 'future'}))
          .label,
      'future',
    );
    expect(
      automationRunStatusLabel(_run(const <String, Object?>{})).label,
      'Unknown',
    );
    expect(
      automationRunStatusLabel(
        _run(<String, Object?>{'status': 'waitingForUser'}),
      ).tone,
      AutomationTone.warning,
    );
  });

  test('recovery without a known budget still names the phase', () {
    expect(
      automationRunStatusLabel(
        _run(<String, Object?>{
          'status': 'dispatched',
          'recovery': <String, Object?>{'status': 'retryingWithContext'},
        }),
      ).label,
      'Retrying With Context',
    );
    expect(
      automationRunStatusLabel(
        _run(<String, Object?>{
          'status': 'dispatched',
          'recovery': <String, Object?>{
            'status': 'reconnecting',
            'code': 'hostUnreachable',
          },
        }),
      ).label,
      'Reconnecting To Host',
    );
  });

  test('recovery that used every attempt is no longer active', () {
    final run = _run(<String, Object?>{
      'status': 'failure',
      'recovery': <String, Object?>{'status': 'exhausted'},
    });
    expect(run.recovery.status, AutomationRecoveryStatus.exhausted);
    expect(run.recovery.isActive, isFalse);
    expect(automationRelativeTime(DateTime.now()), 'now');
  });

  test('durations and relative times stay short', () {
    expect(automationShortDuration(const Duration(days: 2, hours: 3)), '2d');
    expect(automationShortDuration(const Duration(hours: 5)), '5h');
    expect(automationShortDuration(const Duration(minutes: 7)), '7m');
    expect(automationShortDuration(Duration.zero), '1s');
    expect(automationRelativeTime(now, now: now), 'now');
    expect(
      automationRelativeTime(now.add(const Duration(hours: 3)), now: now),
      'in 3h',
    );
    expect(
      automationRelativeTime(
        now.subtract(const Duration(minutes: 5)),
        now: now,
      ),
      '5m ago',
    );
  });

  test('a missed group spans its earliest to latest occurrence', () {
    AutomationRunRecord missed(String id, int hour) => _run(<String, Object?>{
      'id': id,
      'status': 'misfireSkipped',
      'scheduledAt': DateTime.utc(2026, 10, 4, hour).toIso8601String(),
    });
    final history = automationRunHistory(<AutomationRunRecord>[
      missed('a', 9),
      missed('b', 7),
      missed('c', 8),
    ]);
    final group = history.single as AutomationRunHistoryMissed;
    expect(group.from, DateTime.utc(2026, 10, 4, 7));
    expect(group.to, DateTime.utc(2026, 10, 4, 9));
  });

  test('a single missed occurrence stays an ordinary row', () {
    final history = automationRunHistory(<AutomationRunRecord>[
      _run(<String, Object?>{'id': 'a', 'status': 'misfireSkipped'}),
    ]);
    expect((history.single as AutomationRunHistoryRun).run.id, 'a');
  });
}
