import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent status notification tracker', () {
    test('skips states that started before the tracker did', () {
      var now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: now,
      );
      final stale = _entry(
        AgentStatusState.waiting,
        stateStartedAt: DateTime.utc(2026, 5, 26, 11, 59),
      );

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{stale.terminalSessionId: stale},
          includeFinished: true,
        ),
        isEmpty,
      );

      now = DateTime.utc(2026, 5, 26, 12, 1);
      final fresh = stale.copyWith(
        stateStartedAt: now,
        updatedAt: now,
        state: AgentStatusState.done,
      );

      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{stale.terminalSessionId: stale},
          next: <String, AgentStatusEntry>{fresh.terminalSessionId: fresh},
          includeFinished: true,
        ),
        <AgentStatusEntry>[fresh],
      );
    });

    test('skips unchanged states', () {
      var now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: DateTime.utc(2026, 5, 26, 11),
      );
      final waiting = _entry(AgentStatusState.waiting);
      final restated = waiting.copyWith(
        updatedAt: DateTime.utc(2026, 5, 26, 12, 1),
      );

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{waiting.terminalSessionId: waiting},
          includeFinished: true,
        ),
        <AgentStatusEntry>[waiting],
      );

      now = DateTime.utc(2026, 5, 26, 12, 1);
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{
            waiting.terminalSessionId: waiting,
          },
          next: <String, AgentStatusEntry>{
            restated.terminalSessionId: restated,
          },
          includeFinished: true,
        ),
        isEmpty,
      );
    });

    test('holds a repeat of the same state until the cooldown expires', () {
      var now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: DateTime.utc(2026, 5, 26, 11),
        cooldown: const Duration(seconds: 60),
      );
      final first = _entry(AgentStatusState.waiting);

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{first.terminalSessionId: first},
          includeFinished: true,
        ),
        <AgentStatusEntry>[first],
      );

      // A second approval 30s later restarts the state but stays inside the
      // cooldown, so it must not reach the notification centre.
      now = DateTime.utc(2026, 5, 26, 12, 0, 30);
      final tooSoon = first.copyWith(stateStartedAt: now, updatedAt: now);
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{first.terminalSessionId: first},
          next: <String, AgentStatusEntry>{tooSoon.terminalSessionId: tooSoon},
          includeFinished: true,
        ),
        isEmpty,
      );

      now = DateTime.utc(2026, 5, 26, 12, 2);
      final later = first.copyWith(stateStartedAt: now, updatedAt: now);
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{
            tooSoon.terminalSessionId: tooSoon,
          },
          next: <String, AgentStatusEntry>{later.terminalSessionId: later},
          includeFinished: true,
        ),
        <AgentStatusEntry>[later],
      );
    });

    test('collapses the same transition restated with a new start time', () {
      var now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: DateTime.utc(2026, 5, 26, 11),
      );
      final local = _entry(AgentStatusState.done);

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{local.terminalSessionId: local},
          includeFinished: true,
        ),
        <AgentStatusEntry>[local],
      );

      // The runtime snapshot times the same transition a second later, which
      // used to read as a brand new state because the key carried the start.
      now = DateTime.utc(2026, 5, 26, 12, 0, 1);
      final restated = local.copyWith(stateStartedAt: now, updatedAt: now);
      expect(
        tracker.pendingNotifications(
          previous: <String, AgentStatusEntry>{local.terminalSessionId: local},
          next: <String, AgentStatusEntry>{
            restated.terminalSessionId: restated,
          },
          includeFinished: true,
        ),
        isEmpty,
      );
    });

    test('holds done entries back when finished notifications are off', () {
      final now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: DateTime.utc(2026, 5, 26, 11),
      );
      final done = _entry(AgentStatusState.done);
      final waiting = _entry(AgentStatusState.waiting, sessionId: 'session-2');

      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{
            done.terminalSessionId: done,
            waiting.terminalSessionId: waiting,
          },
          includeFinished: false,
        ),
        <AgentStatusEntry>[waiting],
      );
    });

    test('forgets sessions that leave the snapshot', () {
      var now = DateTime.utc(2026, 5, 26, 12);
      final tracker = AgentStatusNotificationTracker(
        now: () => now,
        notifiableFrom: DateTime.utc(2026, 5, 26, 11),
      );
      final waiting = _entry(AgentStatusState.waiting);

      tracker.pendingNotifications(
        previous: const <String, AgentStatusEntry>{},
        next: <String, AgentStatusEntry>{waiting.terminalSessionId: waiting},
        includeFinished: true,
      );
      tracker.pendingNotifications(
        previous: <String, AgentStatusEntry>{
          waiting.terminalSessionId: waiting,
        },
        next: const <String, AgentStatusEntry>{},
        includeFinished: true,
      );

      // The terminal came back inside the cooldown, but its history went away
      // with it, so a fresh run notifies.
      now = DateTime.utc(2026, 5, 26, 12, 0, 10);
      final reopened = waiting.copyWith(stateStartedAt: now, updatedAt: now);
      expect(
        tracker.pendingNotifications(
          previous: const <String, AgentStatusEntry>{},
          next: <String, AgentStatusEntry>{
            reopened.terminalSessionId: reopened,
          },
          includeFinished: true,
        ),
        <AgentStatusEntry>[reopened],
      );
    });
  });
}

AgentStatusEntry _entry(
  AgentStatusState state, {
  String prompt = 'Run tests',
  AgentType agentType = AgentType.codex,
  String sessionId = 'session-1',
  DateTime? updatedAt,
  DateTime? stateStartedAt,
}) {
  return AgentStatusEntry(
    terminalSessionId: sessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: agentType,
    state: state,
    prompt: prompt,
    updatedAt: updatedAt ?? DateTime.utc(2026, 5, 26, 12),
    stateStartedAt: stateStartedAt ?? DateTime.utc(2026, 5, 26, 12),
  );
}
