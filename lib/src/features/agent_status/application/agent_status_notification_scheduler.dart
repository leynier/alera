import 'dart:async';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

/// Quiet period a buffered batch waits for before it is delivered.
const Duration agentStatusNotificationCoalesceWindow = Duration(seconds: 3);

/// Ceiling on how long continuous churn may keep postponing a delivery.
const Duration agentStatusNotificationMaxCoalesceDelay = Duration(seconds: 10);

/// Buffers agent status notifications so a burst becomes one delivery.
///
/// Orchestration settles many terminals at once and a single agent can move
/// twice within a second, so emitting on every state change puts one entry in
/// the notification centre per event. Waiting out a short quiet period lets
/// the coordinator describe the whole burst once.
class AgentStatusNotificationScheduler({
  required final Future<void> Function(List<AgentStatusEntry> batch) emit,
  final Duration coalesceWindow = agentStatusNotificationCoalesceWindow,
  final Duration maxCoalesceDelay = agentStatusNotificationMaxCoalesceDelay,
  final Timer Function(Duration duration, void Function() callback)
      scheduleTimer =
      Timer.new,
  final DateTime Function() now = _systemClock,
}) {
  /// Latest pending entry per terminal session. A terminal that moves from
  /// `waiting` to `done` inside one window is one event to the user, and the
  /// state it ended on is the one worth telling them about.
  final Map<String, AgentStatusEntry> _buffered = <String, AgentStatusEntry>{};

  Timer? _timer;
  DateTime? _bufferedSince;
  var _disposed = false;

  void enqueue(List<AgentStatusEntry> entries) {
    if (_disposed || entries.isEmpty) {
      return;
    }
    for (final entry in entries) {
      _buffered[entry.terminalSessionId] = entry;
    }
    _bufferedSince ??= now();
    final elapsed = now().difference(_bufferedSince!);
    if (elapsed >= maxCoalesceDelay) {
      _timer?.cancel();
      _timer = null;
      unawaited(flush());
      return;
    }
    final remaining = maxCoalesceDelay - elapsed;
    final delay = coalesceWindow < remaining ? coalesceWindow : remaining;
    _timer?.cancel();
    _timer = scheduleTimer(delay, () => unawaited(flush()));
  }

  /// Delivers whatever is buffered now, skipping the remaining quiet period.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    _bufferedSince = null;
    if (_buffered.isEmpty) {
      return;
    }
    final batch = _buffered.values.toList(growable: false);
    _buffered.clear();
    await emit(batch);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _buffered.clear();
    _bufferedSince = null;
  }
}

DateTime _systemClock() => DateTime.now().toUtc();
