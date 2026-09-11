import 'dart:async';

import 'package:alera/src/app/app_navigation.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_job_card.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const BackgroundSetupJobHost({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsState = ref.watch(backgroundSetupJobsProvider);
    final jobs = jobsState.visible;
    if (jobs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(
          right: AleraTokens.space16,
          bottom: AleraTokens.space48,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .end,
          children: <Widget>[
            for (var i = 0; i < jobs.length; i++) ...<Widget>[
              _BackgroundSetupJobCard(
                job: jobs[i],
                onRetry: () => unawaited(_retry(ref, jobs[i])),
                onCancel: jobs[i].canCancel
                    ? () => unawaited(
                        ref
                            .read(backgroundSetupJobsProvider.notifier)
                            .cancel(jobs[i].id),
                      )
                    : null,
                onDismiss: () => ref
                    .read(backgroundSetupJobsProvider.notifier)
                    .dismiss(jobs[i].id),
              ),
              if (i < jobs.length - 1)
                const SizedBox(height: AleraTokens.space8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retry(WidgetRef ref, BackgroundSetupJob job) async {
    final context = aleraNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    switch (job.snapshot) {
      case ManualWorkspaceCreateRequest():
        await showCreateWorkspaceFlow(
          context,
          ref,
          retryManual: job.snapshot as ManualWorkspaceCreateRequest,
          retryError: job.error,
          retryJobId: job.id,
        );
      case PromptWorkspaceCreateRequest():
        await showCreateWorkspaceFlow(
          context,
          ref,
          retryPrompt: job.snapshot as PromptWorkspaceCreateRequest,
          retryError: job.error,
          retryJobId: job.id,
        );
      case ProjectCloneRequest():
        await showAddProjectFlow(
          context,
          ref,
          retryClone: job.snapshot as ProjectCloneRequest,
          retryError: job.error,
          retryJobId: job.id,
        );
    }
  }
}

class const _BackgroundSetupJobCard({
  required final BackgroundSetupJob job,
  required final VoidCallback onRetry,
  required final VoidCallback? onCancel,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = job.progressPercent;
    return AleraJobCard(
      title: job.title,
      status: job.isFailed ? .failed : .running,
      phase: job.phase,
      error: job.error,
      progress: progress == null ? null : progress / 100,
      onRetry: job.canRetry ? onRetry : null,
      onCancel: onCancel,
      onDismiss: job.isFailed ? onDismiss : null,
    );
  }
}
