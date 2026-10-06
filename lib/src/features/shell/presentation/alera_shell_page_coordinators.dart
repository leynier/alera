part of 'alera_shell_page.dart';

/// Keeps the app-wide coordinators alive for as long as the shell is mounted.
void _watchShellCoordinators(WidgetRef ref) {
  ref.watch(terminalHostWarmupCoordinatorProvider);
  ref.watch(runtimeAgentStatusSyncProvider);
  ref.watch(agentStatusNotificationCoordinatorProvider);
  ref.watch(inboxReplyNotificationCoordinatorProvider);
  ref.watch(workspacePullRequestMonitorControllerProvider.notifier);
  ref.watch(workspacePullRequestFailureNotificationCoordinatorProvider);
  ref.watch(workspaceFocusRequestCoordinatorProvider);
  ref.watch(agentAwakeCoordinatorProvider);
  ref.watch(keepAliveCoordinatorProvider);
  ref.watch(terminalRuntimeExitCoordinatorProvider);
  ref.watch(workspaceActivityCoordinatorProvider);
  ref.watch(terminalRuntimeActiveWorkspaceCoordinatorProvider);
  ref.watch(workspaceActivityPersistenceCoordinatorProvider);
}
