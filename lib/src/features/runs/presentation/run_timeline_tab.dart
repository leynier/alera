import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/lists/alera_timeline.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/application/run_participant_labels.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/application/run_timeline_page.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Run events and the messages between its agents, newest first, grouped by
/// day. An open marker still needs something; messages expand in place.
class RunTimelineTab extends ConsumerStatefulWidget {
  const RunTimelineTab({super.key, required this.runId, required this.filter});

  final String runId;
  final RunTimelineFilter filter;

  @override
  ConsumerState<RunTimelineTab> createState() => _RunTimelineTabState();
}

class _RunTimelineTabState extends ConsumerState<RunTimelineTab> {
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final provider = runTimelineProvider(widget.runId, widget.filter);
    final page = ref.watch(provider);
    final navigation = ref.read(activityNavigationProvider.notifier);
    final header = AleraHorizontalScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space8),
        child: AleraSegmentedButton<RunTimelineFilter>(
          key: const ValueKey<String>('runTimelineFilter'),
          dense: true,
          selected: widget.filter,
          onSelectionChanged: navigation.filterTimeline,
          segments: <ButtonSegment<RunTimelineFilter>>[
            for (final filter in RunTimelineFilter.values)
              ButtonSegment<RunTimelineFilter>(
                value: filter,
                label: Text(filter.label),
              ),
          ],
        ),
      ),
    );
    final data = page.hasError ? null : page.value;
    if (data == null) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          header,
          Expanded(
            child: RunReadState(
              error: page.error,
              subject: 'this timeline',
              onRefresh: () => ref.invalidate(provider),
            ),
          ),
        ],
      );
    }
    final now = ref.watch(runClockProvider)();
    final labels = ref.watch(runParticipantLabelsProvider);
    final pendingGates = <String>{
      for (final gate
          in ref
                  .watch(runDetailProvider(widget.runId))
                  .value
                  ?.data
                  .pendingGates ??
              const [])
        gate.id,
    };
    return AleraTimeline(
      key: PageStorageKey<String>('run-timeline:${widget.runId}'),
      header: header,
      emptyMessage: 'No events yet. Dispatches, messages, gates and integrations appear here as the run progresses.',
      footer: RunPageFooter(
        hasMore: data.data.nextCursor != null,
        loading: data.loadingMore,
        error: data.pageError,
        onMore: () => ref.read(provider.notifier).loadOlder(),
        onRefresh: () => ref.invalidate(provider),
        label: 'Load Older Events',
      ),
      entries: <AleraTimelineEntry>[
        for (final entry in data.data.items)
          _entry(entry, now, labels, pendingGates, navigation),
      ],
    );
  }

  AleraTimelineEntry _entry(
    RunTimelineEntry entry,
    DateTime now,
    Map<String, String> labels,
    Set<String> pendingGates,
    ActivityNavigation navigation,
  ) {
    final at = parseRunTimestamp(entry.createdAt) ?? now;
    final gateId = entry.gateId;
    final waiting =
        entry.kind == 'gateOpened' &&
        gateId != null &&
        pendingGates.contains(gateId);
    final body = entry.body?.trim();
    final expandable = entry.carriesMessage && body != null && body.isNotEmpty;
    final expanded = _expanded.contains(entry.id);
    final openDiff = _openDiff(entry);
    return AleraTimelineEntry(
      id: entry.id,
      day: runDayLabel(at, now),
      time: runClockLabel(at),
      title: runTimelineTitle(entry, labels),
      detail: _detail(entry, expanded),
      open: waiting || entry.messageType == 'escalation',
      actions: <Widget>[
        if (waiting)
          TextButton(
            key: ValueKey<String>('runTimelineResolve:$gateId'),
            onPressed: () => navigation.focusGate(widget.runId, gateId),
            child: const Text('Resolve'),
          ),
        if (openDiff != null)
          TextButton(
            key: ValueKey<String>('runTimelineDiff:${entry.id}'),
            onPressed: openDiff,
            child: const Text('Open Diff'),
          ),
        if (expandable)
          TextButton(
            key: ValueKey<String>('runTimelineMore:${entry.id}'),
            onPressed: () => setState(
              () => expanded
                  ? _expanded.remove(entry.id)
                  : _expanded.add(entry.id),
            ),
            child: Text(expanded ? 'Less' : 'More'),
          ),
      ],
      body: expandable && expanded
          ? SelectableText(
              '$body${entry.truncated ? '\n(Truncated. Read the rest in the agent terminal.)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
    );
  }

  /// Completion and integration events that name a commit range open it as
  /// a diff in that workspace, when the workspace is still on this machine.
  VoidCallback? _openDiff(RunTimelineEntry entry) {
    final workspaceId = entry.workspaceId;
    if (!entry.hasDiff || workspaceId == null) return null;
    return runWorkspaceAction(
      context,
      ref,
      workspaceId,
      RunWorkspaceAction.diff,
      committedResult: true,
      resultBaseSha: entry.baseSha,
      resultCompletionSha: entry.sha,
      resultSubject: switch (entry.kind) {
        'integrated' => 'Integrated result',
        'completed' => 'Run result',
        _ => 'Task result',
      },
    );
  }

  String? _detail(RunTimelineEntry entry, bool expanded) {
    if (entry.carriesMessage) {
      if (expanded) return null;
      final text = entry.summary.trim().isNotEmpty
          ? entry.summary.trim()
          : (entry.body ?? '').trim();
      return text.isEmpty ? null : '"${text.split('\n').first}"';
    }
    final summary = entry.summary.trim();
    final actor = entry.actorKind == null || entry.actorKind == 'runtime'
        ? null
        : 'by ${runActorLabel(entry.actorKind, entry.actorId)}';
    final parts = <String>[if (summary.isNotEmpty) summary, ?actor];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// The headline of a timeline row: what happened, and between whom for
/// messages.
String runTimelineTitle(RunTimelineEntry entry, Map<String, String> labels) {
  if (entry.carriesMessage) {
    String name(String? handle) =>
        handle == null ? 'unknown' : participantLabel(labels, handle);
    final route = '${name(entry.from)} -> ${name(entry.to)}';
    return switch (entry.messageType) {
      'escalation' => 'Escalation · $route',
      'question' || 'decision_gate' => 'Question · $route',
      final type? => 'Message · $route · ${type.replaceAll('_', ' ')}',
      null => 'Message · $route',
    };
  }
  return runEventLabel(entry.kind);
}

String runEventLabel(String kind) => switch (kind) {
  'created' => 'Run created',
  'coordinatorStarted' => 'Coordinator started',
  'planProposed' => 'Plan proposed',
  'planApproved' => 'Plan approved',
  'planRejected' => 'Plan rejected',
  'changesRequested' => 'Changes requested',
  'taskCreated' => 'Task created',
  'attemptPrepared' => 'Attempt prepared',
  'dispatched' => 'Dispatched',
  'accepted' => 'Accepted',
  'escalation' => 'Escalation',
  'taskCompleted' => 'Completed',
  'taskFailed' => 'Failed',
  'taskStalled' => 'Stalled',
  'taskCancelled' => 'Task cancelled',
  'gateOpened' => 'Gate opened',
  'gateResolved' => 'Gate resolved',
  'integrationStarted' => 'Integration started',
  'integrated' => 'Integrated',
  'conflict' => 'Conflict',
  'attention' => 'Needs attention',
  'retried' => 'Retried',
  'paused' => 'Paused',
  'resumed' => 'Resumed',
  'cancelled' => 'Run cancelled',
  'completed' => 'Run completed',
  'failed' => 'Run failed',
  'cleanupPrepared' => 'Cleanup prepared',
  'cleanupApplied' => 'Cleanup applied',
  'cleanupAbandoned' => 'Cleanup abandoned',
  final other => other,
};
