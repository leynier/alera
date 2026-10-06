import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

const String inboxChangedEvent = 'inboxChanged';
const String conversationsChangedEvent = 'conversationsChanged';

/// Re-reads on every inbox revision and on host reconnects. Errors reach the
/// UI; recovery is event-driven, so an old host never causes a retry loop.
Stream<T> watchInbox<T>({
  required RuntimeHostClient client,
  required RuntimeChangeCoalescer coalescer,
  required String key,
  required Future<T> Function() read,
  String changedEvent = inboxChangedEvent,
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
          if (event.name == changedEvent ||
              event.name == aleraRuntimeHostConnectedEvent) {
            schedule();
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!disposed) controller.addError(error, stack);
        },
      );
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
