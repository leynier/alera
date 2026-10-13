import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Retry Task and Retry Integration for an isolated attempt that needs them.
/// The runtime only retries while the run is paused and says so otherwise.
class const RunTaskRetryButtons({super.key, required final TaskInspection task})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempt = task.attempt;
    if (attempt == null ||
        (!attempt.canRetry && !attempt.canRetryIntegration)) {
      return const SizedBox.shrink();
    }
    final key = RunActions.taskKey(task.taskId);
    final busy = ref.watch(
      runActionsProvider.select((state) => state.busyFor(key)),
    );
    final error = ref.watch(
      runActionsProvider.select((state) => state.errorFor(key)),
    );
    final integration = attempt.canRetryIntegration;
    return Wrap(
      spacing: AleraTokens.space8,
      crossAxisAlignment: .center,
      children: <Widget>[
        OutlinedButton(
          key: ValueKey<String>(
            integration ? 'runRetryIntegration' : 'runRetryTask',
          ),
          onPressed: busy != null
              ? null
              : () => unawaited(_retry(context, ref, integration)),
          child: Text(
            busy != null
                ? 'Retrying…'
                : integration
                ? 'Retry Integration'
                : 'Retry Task',
          ),
        ),
        if (error != null)
          Tooltip(
            message: runErrorMessage(error),
            child: Text(
              runErrorMessage(error),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    bool integration,
  ) async {
    final actions = ref.read(runActionsProvider.notifier);
    final done = integration
        ? await actions.retryIntegration(task.runId, task.taskId)
        : await actions.retryTask(task.runId, task.taskId);
    if (done && context.mounted) {
      AleraToast.show(
        context,
        message: integration ? 'Integration retried' : 'Task retried',
        tone: AleraToastTone.success,
      );
    }
  }
}
