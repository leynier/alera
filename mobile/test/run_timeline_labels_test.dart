import 'package:alera_mobile/src/features/runs/domain/run_timeline_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_timeline_labels.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kinds = <String>[
  'created', 'coordinatorStarted', 'planProposed', 'planApproved', //
  'planRejected', 'changesRequested', 'taskCreated', 'attemptPrepared',
  'dispatched', 'accepted', 'escalation', 'taskCompleted', 'taskFailed',
  'taskStalled', 'taskCancelled', 'gateOpened', 'gateResolved',
  'integrationStarted', 'integrated', 'conflict', 'attention', 'retried',
  'paused', 'resumed', 'cancelled', 'completed', 'failed',
  'cleanupPrepared', 'cleanupApplied', 'cleanupAbandoned',
];

void main() {
  test('every run event kind has a sentence case label', () {
    for (final kind in _kinds) {
      final label = runEventLabel(kind);
      expect(label, isNot(kind), reason: kind);
      expect(label[0], label[0].toUpperCase(), reason: kind);
      expect(
        label.split(' ').skip(1).where((word) => word != word.toLowerCase()),
        isEmpty,
        reason: kind,
      );
    }
    expect(runEventLabel('someFutureKind'), 'Some future kind');
    expect(runMessageTypeLabel('merge_ready'), 'Merge ready');
    expect(runMessageTypeLabel('decision_gate'), 'Question');
    expect(runMessageTypeLabel(null), 'Message');
  });

  testWidgets('an escalation event shows its route and body', (tester) async {
    final entry = RunTimelineEntry.fromJson(<String, Object?>{
      'id': 'evt-1',
      'source': 'event',
      'kind': 'escalation',
      'createdAt': '2026-09-30 13:58:00',
      'summary': 'The secret is missing',
      'actorKind': 'agent',
      'actorId': 'w-3',
      'messageType': 'escalation',
      'from': 'w-3',
      'to': 'coordinator',
      'body': 'Set OAUTH_SECRET before the next attempt.',
    });
    expect(entry.carriesMessage, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RunTimelineEntryRow(entry: entry)),
      ),
    );
    expect(find.text('w-3 → coordinator'), findsOneWidget);
    expect(
      find.text('Set OAUTH_SECRET before the next attempt.'),
      findsOneWidget,
    );
    expect(find.textContaining('Escalation · agent:w-3'), findsOneWidget);
  });

  testWidgets('an event without a summary falls back to its label', (
    tester,
  ) async {
    final entry = RunTimelineEntry.fromJson(<String, Object?>{
      'id': 'evt-2',
      'kind': 'cleanupApplied',
      'createdAt': '2026-09-30 13:58:00',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RunTimelineEntryRow(entry: entry)),
      ),
    );
    expect(find.text('Cleanup applied'), findsOneWidget);
  });
}
