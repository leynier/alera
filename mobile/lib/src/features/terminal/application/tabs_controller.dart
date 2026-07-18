import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tabs_controller.g.dart';

/// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
/// a desktop concept.
@riverpod
class TabsController extends _$TabsController {
  @override
  Future<List<WorkspaceTabSummary>> build(
    String hostId,
    String workspaceId,
  ) async {
    final client = await ref.watch(terminalClientProvider(hostId).future);
    final subscription = client.events.listen((event) {
      if (event.name == 'workspaceTabsChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    return client.listTabs(workspaceId);
  }

  /// Creates a terminal tab titled after the next free "Terminal N" slot and
  /// returns its tab id.
  Future<String> createTerminalTab() async {
    final client = await ref.read(terminalClientProvider(hostId).future);
    final existing = await future;
    final terminalCount = existing.where((tab) => tab.isTerminal).length;
    final session = await client.createTerminal(
      workspaceId,
      title: 'Terminal ${terminalCount + 1}',
    );
    // The attach that follows owns the session; creating must not keep this
    // controller attached.
    await client.detachTerminal(session.attachment.sessionId);
    ref.invalidateSelf();
    return session.tab.id;
  }

  Future<void> closeTab(WorkspaceTabSummary tab) async {
    final client = await ref.read(terminalClientProvider(hostId).future);
    if (tab.isTerminal) {
      try {
        await client.terminateSession(tab.terminalSessionId);
      } on Object {
        // A tab whose session already exited still gets removed below.
      }
    }
    final workspaceClient = await ref.read(
      workspaceClientProvider(hostId).future,
    );
    await workspaceClient.removeTab(tab.id);
    ref.invalidateSelf();
  }
}
