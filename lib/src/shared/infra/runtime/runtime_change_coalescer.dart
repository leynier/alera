import 'dart:async';

/// Collapses bursts of runtime host change events into at most one refresh per
/// key.
///
/// The host broadcasts one change event per mutation, so orchestration spawning
/// many terminals emits one event per terminal. Without coalescing every one of
/// those costs a socket round-trip per watcher, which is what saturates the
/// single-threaded host actor under load.
class RuntimeChangeCoalescer {
  RuntimeChangeCoalescer({
    this.debounce = const Duration(milliseconds: 120),
    this.maxDelay = const Duration(milliseconds: 600),
  });

  /// Quiet period a key waits for before running.
  final Duration debounce;

  /// Ceiling on how long continuous churn may keep postponing a run. Without
  /// it a trailing debounce would never fire while orchestration keeps
  /// mutating state.
  final Duration maxDelay;

  final Map<String, _CoalescedKey> _keys = <String, _CoalescedKey>{};
  bool _disposed = false;

  /// Schedules [run] for [key], collapsing repeat calls inside the debounce
  /// window into a single run. A call arriving while a run is in flight marks
  /// the key dirty and re-runs exactly once after it settles.
  void schedule(String key, Future<void> Function() run) {
    if (_disposed) {
      return;
    }
    final entry = _keys.putIfAbsent(key, _CoalescedKey.new)..run = run;
    if (entry.inFlight != null) {
      entry.dirty = true;
      return;
    }
    entry.firstScheduledAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(entry.firstScheduledAt!);
    if (elapsed >= maxDelay) {
      entry.timer?.cancel();
      entry.timer = null;
      unawaited(_start(key, entry));
      return;
    }
    final remaining = maxDelay - elapsed;
    final delay = debounce < remaining ? debounce : remaining;
    entry.timer?.cancel();
    entry.timer = Timer(delay, () => unawaited(_start(key, entry)));
  }

  /// Runs [key] now, skipping the debounce but keeping in-flight
  /// de-duplication. Returns once the resulting run settles.
  Future<void> flush(String key) async {
    final entry = _keys[key];
    if (entry == null || entry.run == null) {
      return;
    }
    entry.timer?.cancel();
    entry.timer = null;
    final inFlight = entry.inFlight;
    if (inFlight != null) {
      entry.dirty = true;
      await inFlight;
      if (!identical(_keys[key], entry) || entry.inFlight != null) {
        return;
      }
      // The settled run re-scheduled itself through the debounce; a flush is
      // explicit, so run it now instead of waiting out that window.
      entry.timer?.cancel();
      entry.timer = null;
    }
    await _start(key, entry);
  }

  void cancel(String key) {
    final entry = _keys.remove(key);
    entry?.timer?.cancel();
    entry?.dirty = false;
  }

  void dispose() {
    _disposed = true;
    for (final entry in _keys.values) {
      entry.timer?.cancel();
    }
    _keys.clear();
  }

  Future<void> _start(String key, _CoalescedKey entry) async {
    final run = entry.run;
    if (run == null || !identical(_keys[key], entry)) {
      return;
    }
    entry.timer = null;
    entry.firstScheduledAt = null;
    entry.dirty = false;
    final future = run();
    entry.inFlight = future;
    try {
      await future;
    } finally {
      if (identical(entry.inFlight, future)) {
        entry.inFlight = null;
      }
    }
    if (entry.dirty && identical(_keys[key], entry) && !_disposed) {
      entry.dirty = false;
      // Go back through the debounce rather than re-running straight away.
      // Events that keep landing during a run would otherwise chain into one
      // run per event, which is the fan-out this class exists to prevent.
      schedule(key, run);
    }
  }
}

class _CoalescedKey {
  Timer? timer;
  Future<void>? inFlight;
  bool dirty = false;
  DateTime? firstScheduledAt;
  Future<void> Function()? run;
}
