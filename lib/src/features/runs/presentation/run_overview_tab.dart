import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_key_value_list.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/recipe_catalog_entry.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/presentation/run_actions_bar.dart';
import 'package:alera/src/features/runs/presentation/run_gate_cards.dart';
import 'package:alera/src/features/runs/presentation/run_planning_card.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending gates first (newest on top), then the objective, the run's facts
/// and its actions. [focusGateId] scrolls to a gate a deep link named.
class RunOverviewTab extends ConsumerStatefulWidget {
  const RunOverviewTab({
    super.key,
    required this.snapshot,
    this.focusGateId,
    this.focusSequence = 0,
  });

  final RunSnapshot snapshot;
  final String? focusGateId;
  final int focusSequence;

  @override
  ConsumerState<RunOverviewTab> createState() => _RunOverviewTabState();
}

class _RunOverviewTabState extends ConsumerState<RunOverviewTab> {
  final Map<String, GlobalKey> _gateKeys = <String, GlobalKey>{};
  bool _fullObjective = false;
  int _focusedSequence = -1;

  @override
  void initState() {
    super.initState();
    _scheduleFocus();
  }

  @override
  void didUpdateWidget(RunOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFocus();
  }

  void _scheduleFocus() {
    final gateId = widget.focusGateId;
    if (gateId == null || _focusedSequence == widget.focusSequence) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _gateKeys[gateId]?.currentContext;
      if (!mounted || target == null) return;
      _focusedSequence = widget.focusSequence;
      Scrollable.ensureVisible(
        target,
        duration: AleraTokens.durationMid,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final run = snapshot.run;
    final theme = Theme.of(context);
    final gates = <RunGate>[...snapshot.pendingGates]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final tasks = <String, RunTask>{
      for (final task in snapshot.tasks) task.id: task,
    };
    final focused = widget.focusGateId;
    return ListView(
      key: PageStorageKey<String>('run-overview:${run.id}'),
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: <Widget>[
        for (final gate in gates)
          Padding(
            key: _gateKeys.putIfAbsent(gate.id, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: AleraTokens.space12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: gate.id == focused
                    ? Border.all(color: AleraTokens.accent)
                    : null,
              ),
              child: RunGateCardView(
                gate: gate,
                subject: gate.taskId == null
                    ? null
                    : tasks[gate.taskId]?.title ?? gate.taskId,
                onRefresh: () => ref.invalidate(runDetailProvider(run.id)),
              ),
            ),
          ),
        if (run.status == 'planning') ...<Widget>[
          RunPlanningCard(snapshot: snapshot),
          const SizedBox(height: AleraTokens.space12),
        ],
        const AleraSectionHeader(
          label: 'Objective',
          padding: EdgeInsets.only(bottom: AleraTokens.space4),
        ),
        SelectableText(
          snapshot.objective.isEmpty ? run.objective : snapshot.objective,
          maxLines: _fullObjective ? null : 3,
          style: theme.textTheme.bodyMedium,
        ),
        if (snapshot.objective.split('\n').length > 3 ||
            snapshot.objective.length > 240)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => setState(() => _fullObjective = !_fullObjective),
              child: Text(_fullObjective ? 'Show Less' : 'Show Full'),
            ),
          ),
        if (snapshot.objectiveTruncated)
          Text(
            'The objective preview is truncated.',
            style: theme.textTheme.bodySmall,
          ),
        const AleraSectionHeader(
          label: 'Run',
          padding: EdgeInsets.only(
            top: AleraTokens.space16,
            bottom: AleraTokens.space4,
          ),
        ),
        _RunFacts(snapshot: snapshot),
        const AleraSectionHeader(
          label: 'Actions',
          padding: EdgeInsets.only(
            top: AleraTokens.space16,
            bottom: AleraTokens.space8,
          ),
        ),
        RunActionsBar(snapshot: snapshot),
      ],
    );
  }
}

class const _RunFacts({required final RunSnapshot snapshot})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = snapshot.run;
    final plan = snapshot.plan;
    final now = ref.watch(runClockProvider)();
    final profiles = <String, String>{
      for (final profile in ref.watch(agentProfilesProvider).value ?? const [])
        profile.id: '${profile.name} (${profile.agentType})',
    };
    final view = plan == null
        ? null
        : ref
              .watch(
                runPlanProvider(
                  run.id,
                  revision: plan.revision,
                  state: plan.state,
                ),
              )
              .value;
    final coordinator = snapshot.coordinator;
    final openCoordinator = runWorkspaceAction(
      context,
      ref,
      run.workspaceId,
      RunWorkspaceAction.terminal,
      terminalHandle: coordinator.handle,
    );
    final integration = snapshot.integration;
    return AleraKeyValueList(
      entries: <AleraKeyValue>[
        if (run.isolated)
          AleraKeyValue(
            label: 'Recipe',
            value: <String>[
              _recipeLabel(snapshot, view),
              if (plan != null) 'Revision ${plan.revision}',
            ].join(' · '),
          ),
        AleraKeyValue(
          label: 'Isolation',
          value:
              '${run.isolated ? 'Isolated worktrees' : 'Shared workspace'} · ${snapshot.maxConcurrent} concurrent ${snapshot.maxConcurrent == 1 ? 'worker' : 'workers'}',
        ),
        if (snapshot.sourceSha != null)
          AleraKeyValue(
            label: 'Source',
            value: shortSha(snapshot.sourceSha),
            mono: true,
            copyable: true,
          ),
        if (integration?.sha != null)
          AleraKeyValue(
            label: 'Integration',
            value: <String>[
              shortSha(integration!.sha),
              ?integration.branch,
            ].join(' · '),
            mono: true,
            copyable: true,
          ),
        AleraKeyValue(label: 'Plan', value: _planLabel(snapshot, view, now)),
        AleraKeyValue(
          label: 'Coordinator',
          value: <String>[
            profiles[coordinator.profileId] ??
                coordinator.profileId ??
                'Not recorded',
            _coordinatorState(coordinator.state),
          ].join(' · '),
          trailing: TextButton(
            onPressed: openCoordinator,
            child: const Text('Open Terminal'),
          ),
        ),
        if (snapshot.stopReason != null)
          AleraKeyValue(label: 'Stopped', value: snapshot.stopReason!),
        AleraKeyValue(
          label: 'Run ID',
          value: run.id,
          mono: true,
          copyable: true,
        ),
      ],
    );
  }

  String _recipeLabel(RunSnapshot snapshot, RunPlanView? view) {
    final name = view?.recipeName;
    final source = snapshot.recipeSource;
    final origin = source == null ? null : recipeOriginLabel(source);
    final id = source?['id'] as String? ?? source?['path'] as String?;
    if (name != null) return origin == null ? name : '$name ($origin)';
    if (id == freeformRecipeId) return 'Freeform (Built-in)';
    return id == null
        ? 'Not recorded'
        : '$id${origin == null ? '' : ' ($origin)'}';
  }

  String _planLabel(RunSnapshot snapshot, RunPlanView? view, DateTime now) {
    final plan = snapshot.plan;
    if (plan == null) return 'Not proposed yet';
    final gate = view?.planGate;
    return switch (plan.state) {
      'awaitingApproval' => 'Revision ${plan.revision} · Awaiting approval',
      'planning' => 'Revision ${plan.revision} · Being revised',
      'superseded' => 'Revision ${plan.revision} · Superseded',
      _ when gate != null && gate.resolvedAt != null =>
        'Approved by ${runActorLabel(gate.actorKind, gate.actorId)} · ${runAgeLabel(gate.resolvedAt, now)}',
      _ when !snapshot.run.approvalRequired =>
        'Revision ${plan.revision} · Started without approval',
      _ => 'Revision ${plan.revision} · Approved',
    };
  }

  String _coordinatorState(String state) => switch (state) {
    'reserved' => 'Starting',
    'started' => 'Running',
    'attention' => 'Needs Attention',
    _ => 'Not Started',
  };
}
