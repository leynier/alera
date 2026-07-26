import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_notification_scheduler.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent status notification scheduler', () {
    test('collapses a burst into one batch', () async {
      final timers = _FakeTimers();
      final batches = <List<AgentStatusEntry>>[];
      final scheduler = AgentStatusNotificationScheduler(
        emit: (batch) async => batches.add(batch),
        scheduleTimer: timers.schedule,
        now: () => timers.now,
      );
      addTearDown(scheduler.dispose);

      scheduler.enqueue(<AgentStatusEntry>[_entry(sessionId: 'session-1')]);
      scheduler.enqueue(<AgentStatusEntry>[_entry(sessionId: 'session-2')]);
      expect(batches, isEmpty);

      await timers.fire();

      expect(batches, hasLength(1));
      expect(batches.single.map((entry) => entry.terminalSessionId), <String>[
        'session-1',
        'session-2',
      ]);
    });

    test('keeps only the latest state per terminal', () async {
      final timers = _FakeTimers();
      final batches = <List<AgentStatusEntry>>[];
      final scheduler = AgentStatusNotificationScheduler(
        emit: (batch) async => batches.add(batch),
        scheduleTimer: timers.schedule,
        now: () => timers.now,
      );
      addTearDown(scheduler.dispose);

      scheduler.enqueue(<AgentStatusEntry>[_entry()]);
      scheduler.enqueue(<AgentStatusEntry>[
        _entry(state: AgentStatusState.done),
      ]);
      await timers.fire();

      expect(batches.single, hasLength(1));
      expect(batches.single.single.state, AgentStatusState.done);
    });

    test('stops postponing once the max delay is reached', () async {
      final timers = _FakeTimers();
      final batches = <List<AgentStatusEntry>>[];
      final scheduler = AgentStatusNotificationScheduler(
        emit: (batch) async => batches.add(batch),
        coalesceWindow: const Duration(seconds: 3),
        maxCoalesceDelay: const Duration(seconds: 10),
        scheduleTimer: timers.schedule,
        now: () => timers.now,
      );
      addTearDown(scheduler.dispose);

      scheduler.enqueue(<AgentStatusEntry>[_entry(sessionId: 'session-1')]);
      // Churn keeps arriving just under the quiet period, which a plain
      // trailing debounce would let postpone delivery forever.
      for (var second = 2; second <= 10; second += 2) {
        timers.advance(const Duration(seconds: 2));
        scheduler.enqueue(<AgentStatusEntry>[
          _entry(sessionId: 'session-$second'),
        ]);
      }

      expect(batches, hasLength(1));
      expect(batches.single, hasLength(6));
    });

    test('delivers nothing when the buffer is empty', () async {
      final timers = _FakeTimers();
      var emitted = 0;
      final scheduler = AgentStatusNotificationScheduler(
        emit: (batch) async => emitted++,
        scheduleTimer: timers.schedule,
        now: () => timers.now,
      );
      addTearDown(scheduler.dispose);

      await scheduler.flush();

      expect(emitted, 0);
    });

    test('drops buffered entries once disposed', () async {
      final timers = _FakeTimers();
      var emitted = 0;
      final scheduler = AgentStatusNotificationScheduler(
        emit: (batch) async => emitted++,
        scheduleTimer: timers.schedule,
        now: () => timers.now,
      );

      scheduler.enqueue(<AgentStatusEntry>[_entry()]);
      scheduler.dispose();
      scheduler.enqueue(<AgentStatusEntry>[_entry()]);
      await scheduler.flush();

      expect(emitted, 0);
    });
  });
}

/// Records the pending timer so a test can fire it, and carries the clock the
/// scheduler measures the max delay with.
class _FakeTimers {
  DateTime now = DateTime.utc(2026, 5, 26, 12);
  void Function()? _pending;

  Timer schedule(Duration duration, void Function() callback) {
    _pending = callback;
    return _InertTimer();
  }

  void advance(Duration duration) => now = now.add(duration);

  Future<void> fire() async {
    final callback = _pending;
    _pending = null;
    callback?.call();
    await Future<void>.delayed(Duration.zero);
  }
}

class _InertTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}

AgentStatusEntry _entry({
  String sessionId = 'session-1',
  AgentStatusState state = AgentStatusState.waiting,
}) {
  return AgentStatusEntry(
    terminalSessionId: sessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    state: state,
    prompt: 'Run tests',
    updatedAt: DateTime.utc(2026, 5, 26, 12),
    stateStartedAt: DateTime.utc(2026, 5, 26, 12),
  );
}
