import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

String linuxLauncherDesktopId({String bundleId = kAleraBundleId}) {
  return '$bundleId.desktop';
}

String pendingReviewTooltip(int count) {
  if (count <= 0) {
    return kAleraAppName;
  }
  if (count == 1) {
    return '1 agent needs attention';
  }
  return '$count agents need attention';
}

int pendingReviewCountForTabs({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  return pendingReviewAgentCount(
    visibleWorkspaceAgentRuns(tabs: tabs, agentStatuses: agentStatuses),
  );
}

DesktopPresenceSnapshot desktopPresenceSnapshot({
  required bool showTrayIcon,
  required bool showDockBadge,
  required bool showTrayBadge,
  required int pendingReviewCount,
}) {
  return DesktopPresenceSnapshot(
    trayVisible: showTrayIcon,
    tooltip: pendingReviewTooltip(pendingReviewCount),
    badgeCount: showDockBadge ? pendingReviewCount : 0,
    trayBadgeCount: showTrayBadge ? pendingReviewCount : 0,
  );
}
