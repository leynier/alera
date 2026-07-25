import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

/// Timeout for the bulk list calls behind a snapshot stream.
///
/// The host actor is single-threaded, so a background refresh legitimately
/// queues behind a coordinator sweep or a burst of PTY flushes. The default
/// interactive timeout is too tight for that, and a premature timeout only
/// buys a retry that queues up again.
const Duration runtimeSnapshotRequestTimeout = Duration(seconds: 30);

/// Matches an event payload that carries no scope, i.e. every watcher refreshes.
bool _matchesAnyScope(Map<String, Object?> payload) => true;

/// Builds a scope predicate that accepts an event when it targets [ownId] or
/// when it carries no scope at all.
///
/// A missing or empty scope means wildcard on purpose: an older host broadcasts
/// change events with an empty payload, so the wildcard keeps a new app correct
/// against a host that is already running.
bool Function(Map<String, Object?>) runtimeScopeMatcher(
  String field,
  String ownId,
) {
  return (payload) {
    final scope = payload[field];
    return scope is! String || scope.isEmpty || scope == ownId;
  };
}

/// A stream of snapshots that survives terminal host connection loss.
///
/// The stream never emits an error and never completes on its own. That is the
/// whole point: an `async*` body that throws while reading a snapshot is dead
/// for good, and its listener has no way to tell recoverable IPC failure from
/// intentional completion. Here a failed read schedules a retry instead.
///
/// The retry loop doubles as the reconnect driver. Reading a snapshot goes
/// through [RuntimeHostClient.runtimeRequest], which lazily reopens the socket,
/// so a retry is what brings the connection back. Reconnecting then emits
/// [aleraRuntimeHostConnectedEvent], which force-refreshes every other watcher.
/// One watcher recovering heals the whole tree, so this coupling is deliberate.
Stream<T> runtimeSnapshotStream<T>({
  required RuntimeHostClient client,
  required Set<String> eventNames,
  required Future<T> Function() readSnapshot,
  required String coalesceKey,
  required RuntimeChangeCoalescer coalescer,
  bool Function(Map<String, Object?> payload) matchesScope = _matchesAnyScope,
  Duration retryDelay = const Duration(seconds: 1),
  Duration maxRetryDelay = const Duration(seconds: 15),
}) {
  late final StreamController<T> controller;
  StreamSubscription<RuntimeHostEvent>? eventSub;
  Timer? retryTimer;
  var backoff = retryDelay;

  Future<void> refresh() async {
    if (controller.isClosed) {
      return;
    }
    try {
      final value = await readSnapshot();
      if (controller.isClosed) {
        return;
      }
      controller.add(value);
      backoff = retryDelay;
    } on Object {
      if (controller.isClosed) {
        return;
      }
      retryTimer?.cancel();
      retryTimer = Timer(backoff, () => unawaited(refresh()));
      final next = backoff * 2;
      backoff = next > maxRetryDelay ? maxRetryDelay : next;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      eventSub = client.runtimeEvents.listen(
        (event) {
          if (event.name == aleraRuntimeHostConnectedEvent) {
            retryTimer?.cancel();
            backoff = retryDelay;
            coalescer.schedule(coalesceKey, refresh);
            return;
          }
          if (eventNames.contains(event.name) && matchesScope(event.payload)) {
            coalescer.schedule(coalesceKey, refresh);
          }
        },
        onError: (Object _) {},
        cancelOnError: false,
      );
      unawaited(refresh());
    },
    onCancel: () {
      retryTimer?.cancel();
      retryTimer = null;
      coalescer.cancel(coalesceKey);
      final sub = eventSub;
      eventSub = null;
      return sub?.cancel();
    },
  );
  return controller.stream;
}
