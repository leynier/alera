import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

const String runsChangedEvent = 'runsChanged';
const String recipesChangedEvent = 'recipesChanged';
const String runConversationsChangedEvent = 'conversationsChanged';

/// What makes any run read stale: the board revision, a reconnect, and the
/// project and workspace names rows show.
const Set<String> runRefreshEvents = <String>{
  runsChangedEvent,
  aleraRuntimeHostConnectedEvent,
  'projectsChanged',
  'workspacesChanged',
};

/// Re-reads through the shared coalescer on every [events] name. Errors reach
/// the UI; recovery is explicit or event-driven, so an unsupported host never
/// causes a hidden retry loop.
Stream<T> watchRuns<T>({
  required RuntimeHostClient client,
  required RuntimeChangeCoalescer coalescer,
  required String key,
  required Future<T> Function() read,
  Set<String> events = runRefreshEvents,
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
      final value = await read();
      if (!disposed && generation == connectionGeneration) {
        controller.add(value);
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
          if (events.contains(event.name)) schedule();
        },
        onError: (Object error, StackTrace stack) {
          if (!disposed) controller.addError(error, stack);
        },
      );
      // The first read uses the same lane as events, so a reconnect during it
      // cannot start a second concurrent read.
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
