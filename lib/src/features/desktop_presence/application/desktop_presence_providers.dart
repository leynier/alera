import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_coordinator.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'desktop_presence_providers.g.dart';

@Riverpod(keepAlive: true)
DesktopPresenceBackend desktopPresenceBackend(Ref ref) {
  return MethodChannelDesktopPresenceBackend();
}

@Riverpod(keepAlive: true)
DesktopPresenceCoordinator desktopPresenceCoordinator(Ref ref) {
  final coordinator = DesktopPresenceCoordinator(
    backend: ref.watch(desktopPresenceBackendProvider),
    window: ref.watch(appWindowControllerProvider),
    lifecycle: ref.watch(appWindowLifecycleCoordinatorProvider),
  );
  ref.onDispose(() {
    unawaited(coordinator.destroy());
  });
  return coordinator;
}

int pendingReviewAgentCountFromWorkbench({
  required Map<String, List<WorkspaceTabRecord>> tabsByWorkspace,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  return pendingReviewCountForTabs(
    tabs: tabsByWorkspace.values.expand((tabs) => tabs),
    agentStatuses: agentStatuses,
  );
}

/// Pushes tray visibility and the dock/taskbar badge whenever agent status or
/// the related settings change. No-op off desktop.
@Riverpod(keepAlive: true)
void desktopPresenceSync(Ref ref) {
  if (!supportsDesktopAppWindowState) {
    return;
  }
  final coordinator = ref.watch(desktopPresenceCoordinatorProvider);
  coordinator.start();
  final lifecycle = ref.watch(appWindowLifecycleCoordinatorProvider);
  lifecycle.bindHideOnClose(
    () => ref.read(settingsControllerProvider).general.showTrayIcon,
  );

  void push() {
    final settings = ref.read(settingsControllerProvider).general;
    final count = pendingReviewAgentCountFromWorkbench(
      tabsByWorkspace: ref.read(workbenchControllerProvider).tabsByWorkspace,
      agentStatuses: ref.read(agentStatusControllerProvider),
    );
    unawaited(
      coordinator.apply(
        desktopPresenceSnapshot(
          showTrayIcon: settings.showTrayIcon,
          showDockBadge: settings.showDockBadge,
          pendingReviewCount: count,
        ),
      ),
    );
  }

  ref.listen(settingsControllerProvider.select((s) => s.general.showTrayIcon), (
    _,
    _,
  ) {
    push();
  });
  ref.listen(
    settingsControllerProvider.select((s) => s.general.showDockBadge),
    (_, _) {
      push();
    },
  );
  ref.listen(agentStatusControllerProvider, (_, _) {
    push();
  });
  ref.listen(
    workbenchControllerProvider.select((state) => state.tabsByWorkspace),
    (_, _) {
      push();
    },
  );
  push();
}
