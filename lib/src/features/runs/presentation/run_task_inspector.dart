import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_key_value_list.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/runs/application/run_detail_pages.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/presentation/run_gate_cards.dart';
import 'package:alera/src/features/runs/presentation/run_read_state.dart';
import 'package:alera/src/features/runs/presentation/run_retry_controls.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:alera/src/features/runs/presentation/run_workspace_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One task: its gate, workspace actions, retries, facts, spec, result,
/// evidence and history.
class const RunTaskInspector({
  super.key,
  required final String runId,
  required final String taskId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = runTaskInspectionPageProvider(runId, taskId);
    final page = ref.watch(provider);
    final navigation = ref.read(activityNavigationProvider.notifier);
    final data = page.hasError ? null : page.value;
    final back = Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey<String>('runTaskBack'),
        onPressed: () => navigation.selectTask(null),
        icon: const Icon(AleraIcons.back, size: AleraTokens.iconMd),
        label: const Text('Tasks'),
      ),
    );
    if (data == null) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          back,
          Expanded(
            child: RunReadState(
              error: page.error,
              subject: 'this task',
              onRefresh: () => ref.invalidate(provider),
            ),
          ),
        ],
      );
    }
    final task = data.data;
    final history = task.history;
    return ListView.builder(
      key: PageStorageKey<String>('run-task:$taskId'),
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space16,
        AleraTokens.space16,
      ),
      itemCount: history.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _TaskContent(task: task, back: back);
        if (index == history.length + 1) {
          return RunPageFooter(
            hasMore: task.nextCursor != null,
            loading: data.loadingMore,
            error: data.pageError,
            onMore: () => ref.read(provider.notifier).loadMoreHistory(),
            onRefresh: () => ref.invalidate(provider),
            label: 'Load More History',
          );
        }
        return _HistoryRow(entry: history[index - 1]);
      },
    );
  }
}

class const _TaskContent({
  required final TaskInspection task,
  required final Widget back,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final attempt = task.attempt;
    final status = taskStatusLabel(attempt?.state ?? task.status);
    final workspaceId = task.executionWorkspaceId;
    final committed = attempt != null && task.status == 'completed';
    final pendingGates = task.gates.where((gate) => gate.pending).toList();
    final openTerminal = runWorkspaceAction(
      context,
      ref,
      workspaceId,
      RunWorkspaceAction.terminal,
      terminalHandle: task.terminalHandle,
    );
    Widget section(String label) => AleraSectionHeader(
      label: label,
      padding: const EdgeInsets.only(
        top: AleraTokens.space16,
        bottom: AleraTokens.space4,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          back,
          Text(task.title, style: theme.textTheme.titleMedium),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space4,
            crossAxisAlignment: .center,
            children: <Widget>[
              AleraBadge(label: status.label, tone: status.tone),
              Text(
                <String>[
                  if (task.stageId != null) 'Stage: ${task.stageId}',
                  task.logicalId ?? task.taskId,
                  if (attempt != null) 'Attempt ${attempt.attempt}',
                ].join(' · '),
                style: muted,
              ),
            ],
          ),
          for (final gate in pendingGates)
            RunGateCardView(
              key: ValueKey<String>('taskGate:${gate.id}'),
              gate: gate,
              subject: task.logicalId ?? task.title,
              onShowOutput: openTerminal,
              onRefresh: () => ref.invalidate(
                runTaskInspectionPageProvider(task.runId, task.taskId),
              ),
            ),
          if (attempt?.error != null ||
              (attempt?.conflictPaths ?? const []).isNotEmpty)
            _AttemptProblem(attempt: attempt!),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              OutlinedButton(
                onPressed: runWorkspaceAction(
                  context,
                  ref,
                  workspaceId,
                  RunWorkspaceAction.workspace,
                ),
                child: const Text('Open Workspace'),
              ),
              OutlinedButton(
                onPressed: openTerminal,
                child: const Text('Open Terminal'),
              ),
              OutlinedButton(
                onPressed: runWorkspaceAction(
                  context,
                  ref,
                  workspaceId,
                  RunWorkspaceAction.diff,
                  committedResult: committed,
                  resultBaseSha: attempt?.baseSha,
                  resultCompletionSha: attempt?.completionSha,
                ),
                child: const Text('Open Diff'),
              ),
              RunTaskRetryButtons(task: task),
            ],
          ),
          AleraKeyValueList(
            entries: <AleraKeyValue>[
              AleraKeyValue(
                label: 'Profile',
                value: task.profile ?? 'Not recorded',
              ),
              if (task.terminalHandle != null)
                AleraKeyValue(
                  label: 'Assignee',
                  value: task.terminalHandle!,
                  mono: true,
                ),
              AleraKeyValue(
                label: 'Worktree',
                value:
                    attempt?.worktree ??
                    task.workspacePath ??
                    task.workspaceName ??
                    'Unavailable',
                mono: true,
                copyable: true,
              ),
              if ((attempt?.branch ?? task.branch) != null)
                AleraKeyValue(
                  label: 'Branch',
                  value: attempt?.branch ?? task.branch!,
                  mono: true,
                  copyable: true,
                ),
              AleraKeyValue(
                label: 'Base SHA',
                value: shortSha(attempt?.baseSha ?? task.baseSha).isEmpty
                    ? 'Not recorded'
                    : shortSha(attempt?.baseSha ?? task.baseSha),
                mono: true,
              ),
              if (attempt?.integratedSha != null)
                AleraKeyValue(
                  label: 'Integrated',
                  value: shortSha(attempt!.integratedSha),
                  mono: true,
                ),
              AleraKeyValue(
                label: 'Depends On',
                value: task.dependencies.isEmpty
                    ? 'None'
                    : '${task.dependencies.join(', ')}${task.dependenciesTruncated ? ' (partial)' : ''}',
              ),
            ],
          ),
          section('Spec'),
          SelectableText(
            task.description.isEmpty ? 'No spec recorded.' : task.description,
          ),
          if (task.descriptionTruncated)
            Text('The spec preview is truncated.', style: muted),
          section('Result'),
          SelectableText(
            task.result.summary ??
                task.result.preview ??
                'No result has been submitted.',
          ),
          if (task.result.truncated)
            Text('The result preview is truncated.', style: muted),
          section('Artifacts (${task.result.artifacts.length})'),
          if (task.result.artifacts.isEmpty)
            Text('No artifacts recorded.', style: muted),
          for (final artifact in task.result.artifacts)
            SelectableText(artifact, style: AleraTokens.monoCompactStyle),
          section('Validation (${task.result.validation.length})'),
          Text(
            'Worker-reported evidence is not an independent review.',
            style: muted,
          ),
          for (final item in task.result.validation)
            SelectableText(item, style: AleraTokens.monoCompactStyle),
          section('History'),
          if (task.history.isEmpty)
            Text('No attempts or task events recorded.', style: muted),
        ],
      ),
    );
  }
}

class const _AttemptProblem({required final TaskAttemptInspection attempt})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AleraTokens.space12),
    decoration: BoxDecoration(
      color: AleraTokens.surfaceVariant,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      border: Border.all(color: AleraTokens.borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space4,
      children: <Widget>[
        if (attempt.error != null) SelectableText(attempt.error!),
        if (attempt.conflictPaths.isNotEmpty)
          SelectableText(
            attempt.conflictPaths.join('\n'),
            style: AleraTokens.monoCompactStyle,
          ),
        if (attempt.conflictsTruncated)
          const Text('Additional conflict paths are not shown.'),
      ],
    ),
  );
}

class const _HistoryRow({required final TaskHistoryEntry entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = parseRunTimestamp(entry.occurredAt);
    return Padding(
      key: ValueKey<String>('${entry.kind}:${entry.id}'),
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space4,
        0,
        AleraTokens.space4,
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: AleraTokens.space12,
        children: <Widget>[
          Text(
            at == null ? entry.occurredAt : runClockLabel(at),
            style: AleraTokens.monoCompactStyle,
          ),
          Expanded(
            child: Text(
              <String>[
                '${entry.kind == 'attempt' ? 'Attempt' : 'Event'} · ${taskStatusLabel(entry.status).label}',
                ?entry.summary,
              ].join('   '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
