import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_monitor_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_notifications.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_notification_providers.g.dart';

@Riverpod(keepAlive: true)
void workspacePullRequestFailureNotificationCoordinator(Ref ref) {
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final windowActivator = ref.watch(
    agentStatusNotificationWindowActivatorProvider,
  );
  final tracker = WorkspacePullRequestFailureTracker();
  var initialized = false;
  Future<void>? initializing;

  bool notificationsEnabled() => ref
      .read(settingsControllerProvider)
      .general
      .pullRequestFailureNotificationsEnabled;

  Future<void> activatePayload(String payload) async {
    final decoded = decodeWorkspacePullRequestNotificationPayload(payload);
    if (decoded == null) {
      return;
    }
    await windowActivator.showAndFocus();
    final state = ref.read(workbenchControllerProvider);
    final workspace = findWorkspaceById(state, decoded.workspaceId);
    if (workspace == null) {
      return;
    }
    final project = findProjectById(state, workspace.projectId);
    if (project == null) {
      return;
    }
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: project, workspace: workspace);
  }

  Future<void> ensureInitialized() async {
    if (initialized) {
      return;
    }
    initializing ??= presenter
        .initialize(
          onSelected: (payload) {
            unawaited(activatePayload(payload).catchError(_ignorePrAsyncError));
          },
        )
        .then<void>((_) {
          initialized = true;
        });
    await initializing;
  }

  if (notificationsEnabled()) {
    unawaited(ensureInitialized().catchError(_ignorePrAsyncError));
  }
  ref.listen<bool>(
    settingsControllerProvider.select(
      (settings) => settings.general.pullRequestFailureNotificationsEnabled,
    ),
    (previous, next) {
      if (!next) {
        tracker.reset();
        return;
      }
      tracker.baseline(
        ref.read(workspacePullRequestMonitorControllerProvider).summaries,
      );
      unawaited(ensureInitialized().catchError(_ignorePrAsyncError));
    },
  );

  ref.listen<WorkspacePullRequestMonitorState>(
    workspacePullRequestMonitorControllerProvider,
    (previous, next) {
      if (!notificationsEnabled() ||
          previous?.refreshRevision == next.refreshRevision) {
        return;
      }
      if (previous == null || previous.refreshRevision == 0) {
        tracker.baseline(next.summaries);
        return;
      }
      final failures = tracker.pending(next.summaries);
      if (failures.isEmpty) {
        return;
      }
      unawaited(
        _showWorkspacePullRequestFailureNotifications(
          ref: ref,
          presenter: presenter,
          ensureInitialized: ensureInitialized,
          failures: failures,
        ).catchError(_ignorePrAsyncError),
      );
    },
  );
}

Future<void> _showWorkspacePullRequestFailureNotifications({
  required Ref ref,
  required Future<void> Function() ensureInitialized,
  required AgentStatusNotificationPresenter presenter,
  required List<WorkspacePullRequestFailure> failures,
}) async {
  await ensureInitialized();
  final state = ref.read(workbenchControllerProvider);
  for (final failure in failures) {
    final workspace = findWorkspaceById(state, failure.workspaceId);
    final project = workspace == null
        ? null
        : findProjectById(state, workspace.projectId);
    await presenter.show(
      composeWorkspacePullRequestFailureNotification(
        failure: failure,
        projectName: project?.name,
        workspaceName: workspace?.name,
      ),
    );
  }
}

void _ignorePrAsyncError(Object _, StackTrace _) {}
