import 'dart:async';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_operations.g.dart';

class const BackgroundOperation({
  required final String id,
  required final String title,
  final String? error,
  final void Function()? restore,
});

/// Owns submissions after their form closes. Failed writes are never replayed
/// automatically: the server may already have applied part of the operation.
@Riverpod(keepAlive: true)
class BackgroundOperations extends _$BackgroundOperations {
  int _sequence = 0;

  @override
  List<BackgroundOperation> build() => const [];

  void dismiss(String id) {
    state = [
      for (final job in state)
        if (job.id != id) job,
    ];
  }

  bool submit({
    String? operationKey,
    required String title,
    required Future<String?> Function() action,
    void Function()? restore,
    void Function()? onSuccess,
  }) {
    if (operationKey != null &&
        state.any((job) => job.id == operationKey && job.error == null)) {
      return false;
    }
    final id = operationKey ?? 'operation-${_sequence++}';
    state = [
      for (final job in state)
        if (job.id != id) job,
    ];
    state = [...state, BackgroundOperation(id: id, title: title)];
    unawaited(_run(id, title, action, restore, onSuccess));
    return true;
  }

  Future<void> _run(
    String id,
    String title,
    Future<String?> Function() action,
    void Function()? restore,
    void Function()? onSuccess,
  ) async {
    String? failure;
    try {
      failure = await action();
    } on Object catch (error, stack) {
      Logger('BackgroundOperations').warning(title, error, stack);
      failure = error.toString();
    }
    if (!ref.mounted) return;
    if (failure == null) {
      dismiss(id);
      onSuccess?.call();
    } else {
      Logger('BackgroundOperations').warning('$title: $failure');
      state = [
        for (final job in state)
          if (job.id == id)
            BackgroundOperation(
              id: id,
              title: title,
              error: failure,
              restore: restore,
            )
          else
            job,
      ];
    }
  }
}
