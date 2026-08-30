import 'dart:async';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';

/// Cancel, rather than pause, the upstream so hidden windows do no reads.
Stream<T> foregroundBoardWatch<T>(
  AppForeground foreground,
  Stream<T> Function() watch,
) {
  late final StreamController<T> controller;
  StreamSubscription<bool>? visibility;
  StreamSubscription<T>? source;
  var generation = 0;
  var disposed = false;
  Future<void> change(bool visible) async {
    final current = ++generation;
    final previous = source;
    source = null;
    await previous?.cancel();
    if (disposed || current != generation || !visible) return;
    source = watch().listen(
      (value) {
        if (!disposed && current == generation) controller.add(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!disposed && current == generation) {
          controller.addError(error, stack);
        }
      },
    );
  }

  controller = StreamController<T>(
    onListen: () {
      visibility = foreground.changes.listen(
        (visible) => unawaited(change(visible)),
      );
      unawaited(change(foreground.isForeground));
    },
    onCancel: () async {
      disposed = true;
      generation++;
      // Start both cancellations immediately; one slow upstream must not keep
      // the other reading after the Board's owner has disappeared.
      await Future.wait<void>([
        if (visibility != null) visibility!.cancel(),
        if (source != null) source!.cancel(),
      ]);
    },
  );
  return controller.stream;
}
