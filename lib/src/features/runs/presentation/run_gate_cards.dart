import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_gate_card.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/presentation/run_gate_review.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _notesLabel = 'Notes (required to reject or request changes)';

/// The options a person can pick for [gate], with the runtime's option ids.
List<AleraGateCardOption> runGateOptions(RunGate gate) => switch (gate.kind) {
  RunGateKind.plan || RunGateKind.stage => <AleraGateCardOption>[
    const AleraGateCardOption(
      id: RunGateOptions.reject,
      label: 'Reject',
      busyLabel: 'Rejecting…',
      destructive: true,
      requiresNotes: true,
    ),
    const AleraGateCardOption(
      id: RunGateOptions.requestChanges,
      label: 'Request Changes',
      busyLabel: 'Requesting Changes…',
      requiresNotes: true,
    ),
    AleraGateCardOption(
      id: RunGateOptions.approve,
      label: gate.kind == RunGateKind.plan ? 'Approve Plan' : 'Approve Gate',
      busyLabel: 'Approving…',
      primary: true,
    ),
  ],
  RunGateKind.stall => const <AleraGateCardOption>[
    AleraGateCardOption(
      id: RunGateOptions.abortStage,
      label: 'Abort Stage',
      busyLabel: 'Aborting…',
      destructive: true,
    ),
    AleraGateCardOption(
      id: RunGateOptions.keepWaiting,
      label: 'Keep Waiting',
      busyLabel: 'Keeping…',
    ),
    AleraGateCardOption(
      id: RunGateOptions.killAndFailover,
      label: 'Kill And Failover',
      busyLabel: 'Failing Over…',
      primary: true,
    ),
  ],
  RunGateKind.decision => <AleraGateCardOption>[
    for (final option in gate.options)
      AleraGateCardOption(id: option, label: option, busyLabel: 'Sending…'),
  ],
};

/// What a successful decision says, mirroring what the runtime did.
String runGateDecisionToast(RunGate gate, String decision) =>
    switch ((gate.kind, decision)) {
      (RunGateKind.plan, RunGateOptions.approve) => 'Plan approved',
      (RunGateKind.stage, RunGateOptions.approve) => 'Gate approved',
      (_, RunGateOptions.requestChanges) => 'Changes requested',
      (RunGateKind.plan, RunGateOptions.reject) => 'Plan rejected',
      (RunGateKind.stage, RunGateOptions.reject) => 'Gate rejected',
      (RunGateKind.stall, RunGateOptions.killAndFailover) => 'Worker replaced',
      (RunGateKind.stall, RunGateOptions.keepWaiting) => 'Still waiting',
      (RunGateKind.stall, RunGateOptions.abortStage) => 'Stage aborted',
      _ => 'Answer sent',
    };

/// One pending gate as a card: decides through [RunActions] with the gate's
/// evidence digest, so a gate that changed meanwhile comes back stale.
class RunGateCardView extends ConsumerStatefulWidget {
  const RunGateCardView({
    super.key,
    required this.gate,
    this.subject,
    this.onRefresh,
    this.onShowOutput,
  });

  final RunGate gate;

  /// What the gate is about: a task title or a stage title.
  final String? subject;

  /// Re-reads whatever listed this gate.
  final VoidCallback? onRefresh;

  /// Opens the stalled worker's terminal.
  final VoidCallback? onShowOutput;

  @override
  ConsumerState<RunGateCardView> createState() => _RunGateCardViewState();
}

class _RunGateCardViewState extends ConsumerState<RunGateCardView> {
  bool _expanded = false;

  RunGate get _gate => widget.gate;

  Future<void> _decide(String optionId, String notes) async {
    final decision = optionId == AleraGateCard.otherOptionId ? notes : optionId;
    final reason = optionId == AleraGateCard.otherOptionId ? null : notes;
    final accepted = await ref
        .read(runActionsProvider.notifier)
        .resolveGate(_gate, decision, reason: reason);
    if (accepted && mounted) {
      AleraToast.show(
        context,
        message: runGateDecisionToast(_gate, decision),
        tone: AleraToastTone.success,
      );
    }
  }

  void _refresh() {
    ref.read(runActionsProvider.notifier).clearGate(_gate.id);
    ref.invalidate(runGateDetailProvider(_gate.id));
    widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final gate = _gate;
    final actions = ref.watch(runActionsProvider);
    final key = RunActions.gateKey(gate.id);
    final busy = actions.busyFor(key);
    final options = runGateOptions(gate);
    final error = actions.errorFor(key);
    final status = runGateStatusLabel(gate.status);
    final reviewable =
        gate.kind == RunGateKind.plan || gate.kind == RunGateKind.stage;
    return AleraGateCard(
      key: ValueKey<String>('runGate:${gate.id}'),
      kindLabel: runGateKindLabel(gate.kind),
      title: _title(gate),
      statusLabel: status.label,
      statusTone: status.tone,
      statusDetail: gate.pending && !gate.due ? 'Waiting for evidence' : null,
      prompt: _prompt(gate),
      meta: gate.kind == RunGateKind.decision
          ? 'Asked at ${runClockLabel(parseRunTimestamp(gate.createdAt) ?? DateTime.now())}.'
          : null,
      links: <Widget>[
        if (reviewable)
          TextButton(
            key: ValueKey<String>('runGateReview:${gate.id}'),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? 'Hide Details'
                  : gate.kind == RunGateKind.plan
                  ? 'Review Plan'
                  : 'View Evidence',
            ),
          ),
        if (gate.kind == RunGateKind.stall && widget.onShowOutput != null)
          TextButton(
            onPressed: widget.onShowOutput,
            child: const Text('Show Output'),
          ),
      ],
      body: _expanded ? _RunGateDetailBody(gateId: gate.id) : null,
      options: options,
      notesLabel: reviewable ? _notesLabel : null,
      allowOther: gate.kind == RunGateKind.decision,
      busyOptionId: busy == null
          ? null
          : options.any((option) => option.id == busy)
          ? busy
          : AleraGateCard.otherOptionId,
      stale: actions.isStale(gate.id),
      onRefresh: _refresh,
      error: error == null ? null : runErrorMessage(error),
      enabled: gate.actionable,
      onSelected: (id, notes) => unawaited(_decide(id, notes)),
    );
  }

  String? _title(RunGate gate) {
    final subject = widget.subject;
    return switch (gate.kind) {
      RunGateKind.plan =>
        gate.planRevision == null ? null : 'Revision ${gate.planRevision}',
      RunGateKind.stage => subject ?? (gate.scope.isEmpty ? null : gate.scope),
      _ => subject ?? gate.taskId,
    };
  }

  String _prompt(RunGate gate) {
    final question = gate.question.trim();
    return switch (gate.kind) {
      RunGateKind.plan =>
        '${question.isEmpty ? 'The coordinator proposed a plan.' : question} Approving freezes this plan and starts the workers.',
      RunGateKind.stage when question.isEmpty =>
        'This stage is ready for review. Approval binds this revision, integration ${shortSha(gate.integrationSha)} and the artifact evidence. Changed evidence needs another review.',
      RunGateKind.stall when question.isEmpty => 'This worker has shown no activity. It may still be running, so Alera will not respawn it without a decision.',
      _ => question,
    };
  }
}

/// The plan (plan gates) or evidence (stage gates) behind a card.
class const _RunGateDetailBody({required final String gateId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(runGateDetailProvider(gateId));
    final value = detail.hasError ? null : detail.value;
    if (value == null) {
      return SizedBox(
        height: AleraTokens.space48 * 3,
        child: RunReadState(
          error: detail.error,
          subject: 'this gate',
          onRefresh: () => ref.invalidate(runGateDetailProvider(gateId)),
        ),
      );
    }
    final plan = value.plan;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space12,
      children: <Widget>[
        if (plan != null) RunPlanReview(plan: plan),
        if (value.gate.kind != RunGateKind.plan) RunGateEvidence(detail: value),
      ],
    );
  }
}
