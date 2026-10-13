import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/presentation/run_actions_bar.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a run in Planning shows: the coordinator is writing the plan, or it
/// could not start.
class const RunPlanningCard({super.key, required final RunSnapshot snapshot})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = snapshot.coordinator;
    final failed = coordinator.state == 'attention';
    final busy = ref.watch(
      runActionsProvider.select(
        (state) => state.busyFor(RunActions.runKey(snapshot.run.id)),
      ),
    );
    final openTerminal = runWorkspaceAction(
      context,
      ref,
      snapshot.run.workspaceId,
      RunWorkspaceAction.terminal,
      terminalHandle: coordinator.handle,
    );
    final reason = snapshot.plan?.changeReason?.trim();
    return AleraInlineNotice(
      key: const ValueKey<String>('runPlanningCard'),
      tone: failed ? .error : .info,
      message: failed
          ? 'The coordinator could not start${coordinator.error == null ? '.' : ': ${coordinator.error}'}'
          : reason != null && reason.isNotEmpty
          ? 'Coordinator is preparing a revised plan… Requested changes: $reason'
          : 'Coordinator is preparing a plan…',
      child: Wrap(
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          OutlinedButton(
            key: const ValueKey<String>('runOpenCoordinator'),
            onPressed: openTerminal,
            child: const Text('Open Coordinator Terminal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AleraTokens.error),
            onPressed: busy != null
                ? null
                : () => unawaited(confirmCancelRun(context, ref, snapshot)),
            child: Text(busy == 'cancel' ? 'Cancelling…' : 'Cancel Run'),
          ),
        ],
      ),
    );
  }
}
