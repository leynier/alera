import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_actions.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_inspection_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_gate_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One task: its spec, result, attempt, gates and history.
class const RunTaskScreen({
  super.key,
  required final String hostId,
  required final String runId,
  required final String taskId,
  final String title = 'Task',
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileRunTaskProvider(hostId, runId, taskId);
    final task = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          task.value?.title ?? title,
          maxLines: 1,
          overflow: .ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (task) {
          AsyncValue(value: final RunTaskInspection value) => RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: _TaskBody(
              hostId: hostId,
              runId: runId,
              task: value,
              offline: task.hasError,
            ),
          ),
          AsyncValue(hasError: true, :final error) => AleraEmptyState(
            icon: AleraIcons.loadFailed,
            title: 'Task Unavailable',
            message: runErrorMessage(error!),
            action: TextButton(
              onPressed: () => ref.invalidate(provider),
              child: const Text('Retry'),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class const _TaskBody({
  required final String hostId,
  required final String runId,
  required final RunTaskInspection task,
  required final bool offline,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final attempt = task.attempt;
    final status = runTaskStatusLabel(
      task.status,
      attemptState: attempt?.state,
    );
    final result = task.result;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        if (offline)
          const Padding(
            padding: EdgeInsets.only(bottom: AleraTokens.space8),
            child: AleraNotice(
              message: 'Offline. Showing the last state of this task.',
            ),
          ),
        Row(
          children: <Widget>[
            AleraBadge(label: status.label, tone: status.tone),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                <String>[
                  ?task.stageId,
                  ?task.profile,
                  ?task.workspaceName,
                ].join(' · '),
                maxLines: 2,
                overflow: .ellipsis,
                style: muted,
              ),
            ),
          ],
        ),
        for (final gate in task.gates.where((gate) => gate.isOpen))
          RunGateSection(hostId: hostId, runId: runId, gate: gate),
        if (task.description.isNotEmpty) ...<Widget>[
          const AleraSectionHeader(label: 'Spec'),
          SelectableText(task.description),
          if (task.descriptionTruncated)
            Text('The spec is longer than this preview.', style: muted),
        ],
        if (result.summary != null || result.preview != null) ...<Widget>[
          const AleraSectionHeader(label: 'Result'),
          if (result.summary case final summary?) SelectableText(summary),
          if (result.preview case final preview?) ...<Widget>[
            const SizedBox(height: AleraTokens.space4),
            SelectableText(preview, style: AleraTokens.monoStyle),
          ],
          if (result.validation.isNotEmpty)
            Text('Validation: ${result.validation.join(', ')}', style: muted),
          if (result.artifacts.isNotEmpty)
            Text('Artifacts: ${result.artifacts.join(', ')}', style: muted),
        ],
        if (attempt != null) ...<Widget>[
          AleraSectionHeader(label: 'Attempt ${attempt.attempt}'),
          if (attempt.branch case final branch?)
            Text('Branch $branch', style: muted),
          if (attempt.completionSha case final sha?)
            Text('Result ${shortSha(sha)}', style: muted),
          if (attempt.integratedSha case final sha?)
            Text('Integrated at ${shortSha(sha)}', style: muted),
          if (attempt.conflictPaths.isNotEmpty)
            Text(
              'Conflicts: ${attempt.conflictPaths.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          if (attempt.error case final error?)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.warning,
              ),
            ),
          const SizedBox(height: AleraTokens.space8),
          _RetryButtons(
            hostId: hostId,
            runId: runId,
            taskId: task.taskId,
            canRetry: attempt.canRetry,
            canRetryIntegration: attempt.canRetryIntegration,
          ),
        ],
        if (task.history.isNotEmpty) ...<Widget>[
          const AleraSectionHeader(label: 'History'),
          for (final entry in task.history)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(entry.summary ?? entry.kind),
              subtitle: Text(
                <String>[
                  entry.status,
                  runAgeLabel(entry.occurredAt, DateTime.now().toUtc()),
                ].where((part) => part.isNotEmpty).join(' · '),
                style: muted,
              ),
            ),
        ],
      ],
    );
  }
}

/// Retry Task and Retry Integration, offered only when the attempt allows
/// them. The runtime refuses both unless the run is paused.
class const _RetryButtons({
  required final String hostId,
  required final String runId,
  required final String taskId,
  required final bool canRetry,
  required final bool canRetryIntegration,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canRetry && !canRetryIntegration) return const SizedBox.shrink();
    final provider = mobileRunActionsProvider(hostId, runId);
    final actions = ref.watch(provider);
    Future<void> guarded(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
      } on Object catch (error, stackTrace) {
        showActionFailure(
          messenger,
          action: 'retry the task',
          error: error,
          stackTrace: stackTrace,
          message: runErrorMessage(error),
        );
      }
    }

    return Wrap(
      spacing: AleraTokens.space8,
      children: <Widget>[
        if (canRetry)
          OutlinedButton(
            onPressed: actions.isBusy(runTaskRetryKey(taskId))
                ? null
                : () => unawaited(
                    guarded(
                      () => ref.read(provider.notifier).retryTask(taskId),
                    ),
                  ),
            child: const Text('Retry Task'),
          ),
        if (canRetryIntegration)
          OutlinedButton(
            onPressed: actions.isBusy(runIntegrationRetryKey(taskId))
                ? null
                : () => unawaited(
                    guarded(
                      () =>
                          ref.read(provider.notifier).retryIntegration(taskId),
                    ),
                  ),
            child: const Text('Retry Integration'),
          ),
      ],
    );
  }
}
