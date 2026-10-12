import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_actions.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_overview_tab.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_task_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a run, optionally scrolled to one of its gates.
Future<void> openRun(
  BuildContext context,
  String hostId,
  String runId, {
  String? gateId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) =>
        RunDetailScreen(hostId: hostId, runId: runId, initialGateId: gateId),
  ),
);

/// One run: Overview (gates first), Tasks and Timeline. Renders from the last
/// snapshot, so a reconnect keeps the screen and its tab.
class const RunDetailScreen({
  super.key,
  required final String hostId,
  required final String runId,
  final String? initialGateId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileRunDetailProvider(hostId, runId);
    final snapshot = ref.watch(provider);
    final detail = snapshot.value;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            detail == null || detail.objective.isEmpty
                ? 'Run'
                : detail.objective,
            maxLines: 1,
            overflow: .ellipsis,
          ),
          actions: <Widget>[
            if (detail != null)
              IconButton(
                tooltip: 'More Actions',
                icon: const Icon(AleraIcons.more),
                onPressed: () => unawaited(
                  showRunActions(context, ref, hostId: hostId, detail: detail),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (snapshot) {
            AsyncValue(value: final RunDetail detail) => Column(
              children: <Widget>[
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AleraTokens.space16,
                      AleraTokens.space8,
                      AleraTokens.space16,
                      0,
                    ),
                    child: AleraNotice(
                      message:
                          'Offline. Showing the last snapshot of this run.',
                    ),
                  ),
                _RunHeader(detail: detail),
                const TabBar(
                  tabs: <Widget>[
                    Tab(text: 'Overview'),
                    Tab(text: 'Tasks'),
                    Tab(text: 'Timeline'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      RunOverviewTab(
                        hostId: hostId,
                        detail: detail,
                        initialGateId: initialGateId,
                      ),
                      _RunTasksTab(hostId: hostId, detail: detail),
                      RunTimelineView(hostId: hostId, runId: runId),
                    ],
                  ),
                ),
              ],
            ),
            AsyncValue(hasError: true, :final error) => AleraEmptyState(
              icon: error is RunsUpdateRequired
                  ? AleraIcons.systemUpdate
                  : AleraIcons.loadFailed,
              title: 'Run Unavailable',
              message: runErrorMessage(error!),
              action: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry'),
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class const _RunHeader({required final RunDetail detail})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final run = detail.run;
    final status = runStatusLabel(run);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final age = runAgeLabel(
      run.lastActivityAt ?? run.createdAt,
      DateTime.now().toUtc(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space8,
        AleraTokens.space16,
        AleraTokens.space4,
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AleraBadge(label: status.label, tone: status.tone),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  run.workspaceLabel,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            <String>[
              runProgressLabel(run),
              if (age.isNotEmpty) age,
            ].join(' · '),
            style: muted,
          ),
        ],
      ),
    );
  }
}

class const _RunTasksTab({
  required final String hostId,
  required final RunDetail detail,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (detail.tasks.isEmpty) {
      return AleraEmptyState(
        icon: AleraIcons.workspaceChildren,
        message: detail.run.status == 'planning'
            ? 'The coordinator is planning. Tasks appear once it proposes a plan.'
            : 'This run has no tasks.',
      );
    }
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        for (final task in detail.tasks)
          RunTaskRow(
            task: task,
            onOpen: () => unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RunTaskScreen(
                    hostId: hostId,
                    runId: detail.run.id,
                    taskId: task.id,
                    title: task.title,
                  ),
                ),
              ),
            ),
          ),
        if (detail.nextTaskId != null)
          const Padding(
            padding: EdgeInsets.all(AleraTokens.space8),
            child: Text(
              'Showing the first tasks of this run. Open the desktop for the rest.',
              textAlign: .center,
            ),
          ),
      ],
    );
  }
}

/// One task: title, status, stage and who runs it.
class const RunTaskRow({
  super.key,
  required final RunTask task,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = runTaskStatusLabel(
      task.status,
      attemptState: task.attemptState,
    );
    final age = runAgeLabel(task.updatedAt, DateTime.now().toUtc());
    final meta = <String>[
      ?task.stageId,
      ?(task.assignee ?? task.profile),
      if (task.attempt case final attempt? when attempt.attempt > 1)
        'Attempt ${attempt.attempt}',
      if (age.isNotEmpty) age,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: ListTile(
        onTap: onOpen,
        title: Text(task.title, maxLines: 2, overflow: .ellipsis),
        subtitle: meta.isEmpty
            ? null
            : Text(
                meta,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
        trailing: AleraBadge(label: status.label, tone: status.tone),
      ),
    );
  }
}
