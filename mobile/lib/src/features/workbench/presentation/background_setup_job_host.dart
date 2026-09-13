import 'dart:async';

import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_job_card.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const BackgroundSetupJobHost({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsState = ref.watch(backgroundSetupJobsProvider);
    if (jobsState.jobs.isEmpty || jobsState.retryLocked) {
      return const SizedBox.shrink();
    }
    final jobs = jobsState.jobs;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.spaceLg),
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            for (final job in jobs)
              AleraJobCard(
                title: job.title,
                status: job.isFailed ? .failed : .running,
                phase: job.phase,
                error: job.error,
                onRetry: job.canRetry
                    ? () => unawaited(_retry(context, ref, job))
                    : null,
                onDismiss: job.isFailed
                    ? () => ref
                          .read(backgroundSetupJobsProvider.notifier)
                          .dismiss(job.id)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _retry(
  BuildContext context,
  WidgetRef ref,
  BackgroundSetupJob job,
) async {
  final jobs = ref.read(backgroundSetupJobsProvider.notifier);
  if (!jobs.beginRetryNavigation()) {
    return;
  }
  try {
    await _openRetryForm(context, ref, job);
  } finally {
    jobs.endRetryNavigation();
  }
}

Future<void> _openRetryForm(
  BuildContext context,
  WidgetRef ref,
  BackgroundSetupJob job,
) async {
  final snapshot = job.snapshot;
  final hostId = switch (snapshot) {
    final ManualWorkspaceCreateRequest request => request.hostId,
    final PromptWorkspaceCreateRequest request => request.hostId,
    _ => null,
  };
  if (hostId == null) {
    return;
  }
  final navigator = aleraNavigatorKey.currentState ?? Navigator.of(context);
  final list = await ref.read(workspaceListControllerProvider(hostId).future);
  final linkedIssues = await ref
      .read(linkedIssuesControllerProvider(hostId).future)
      .then((snapshot) => snapshot.supported, onError: (_) => false);
  if (!navigator.mounted) {
    return;
  }
  await navigator.push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => switch (snapshot) {
        final ManualWorkspaceCreateRequest request => CreateWorkspaceScreen(
          hostId: hostId,
          projects: list.projects,
          workspaces: list.workspaces,
          defaultAgentProfileId: list.defaultAgentProfileId,
          supportsPromptWorkspaceCreation: list.supportsPromptWorkspaceCreation,
          supportsPromptImageUpload: list.supportsPromptImageUpload,
          supportsPromptFileUpload: list.supportsPromptFileUpload,
          supportsWorkspaceFiles: list.supportsWorkspaceFiles,
          retryJobId: job.id,
          initialError: job.error,
          initialFromPrompt: false,
          initialProjectId: request.projectId,
          initialSourceBranch: request.sourceBranch,
          initialParentWorkspaceId: request.parentWorkspaceId,
          initialBranch: request.branch,
          initialName: request.name,
          initialReuseExistingBranch: request.reuseExistingBranch,
          supportsLinkedIssues: linkedIssues,
          initialIssueUrl: request.issueUrl,
        ),
        final PromptWorkspaceCreateRequest request => CreateWorkspaceScreen(
          hostId: hostId,
          projects: list.projects,
          workspaces: list.workspaces,
          defaultAgentProfileId: request.profileId,
          supportsPromptWorkspaceCreation: list.supportsPromptWorkspaceCreation,
          supportsPromptImageUpload: list.supportsPromptImageUpload,
          supportsPromptFileUpload: list.supportsPromptFileUpload,
          supportsWorkspaceFiles: list.supportsWorkspaceFiles,
          retryJobId: job.id,
          initialError: job.error,
          initialFromPrompt: true,
          initialPrompt: request.prompt,
          initialProjectId: request.projectId,
          initialSourceBranch: request.sourceBranch,
          initialProfileId: request.profileId,
          initialParentWorkspaceId: request.parentWorkspaceId,
          supportsLinkedIssues: linkedIssues,
          initialIssueUrl: request.issueUrl,
        ),
        _ => CreateWorkspaceScreen(
          hostId: hostId,
          projects: list.projects,
          workspaces: list.workspaces,
        ),
      },
    ),
  );
}
