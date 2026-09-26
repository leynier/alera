import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

const runBoardChangedEvent = 'orchestrationBoardChanged';

/// Unlike legacy snapshot watchers, errors reach the UI. Recovery is explicit
/// or event-driven: an unsupported host must not cause a hidden retry loop.
Stream<T> watchRunBoard<T>({
  required RuntimeHostClient client,
  required RuntimeChangeCoalescer coalescer,
  required String key,
  required Future<T> Function() read,
}) {
  final owner = Object();
  late final StreamController<T> controller;
  StreamSubscription<RuntimeHostEvent>? subscription;
  var disposed = false;
  var connectionGeneration = 0;

  Future<void> refresh() async {
    if (disposed) return;
    final generation = connectionGeneration;
    try {
      final snapshot = await read();
      if (!disposed && generation == connectionGeneration) {
        controller.add(snapshot);
      }
    } on Object catch (error, stack) {
      if (!disposed && generation == connectionGeneration) {
        controller.addError(error, stack);
      }
    }
  }

  void schedule() => coalescer.schedule(key, owner, refresh);

  controller = StreamController<T>(
    onListen: () {
      subscription = client.runtimeEvents.listen(
        (event) {
          if (event.name == aleraRuntimeHostDisconnectedEvent) {
            connectionGeneration++;
            controller.addError(const TerminalHostConnectionClosedException());
            return;
          }
          if ({
            runBoardChangedEvent,
            aleraRuntimeHostConnectedEvent,
            'projectsChanged',
            'workspacesChanged',
          }.contains(event.name)) {
            schedule();
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!disposed) controller.addError(error, stack);
        },
      );
      // Initial fetch uses the same lane as events, so a reconnect during the
      // first request cannot launch a second concurrent snapshot.
      schedule();
      unawaited(coalescer.flush(key));
    },
    onCancel: () async {
      disposed = true;
      coalescer.cancel(key, owner);
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
