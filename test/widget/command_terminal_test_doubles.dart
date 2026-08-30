import 'dart:async';

import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Session handle standing in for a live PTY. [isRunning] is what decides
/// whether closing the command dialog asks for confirmation, so tests set it
/// directly.
class FakeCommandTerminalSession({
  this.tabId = 'command-tab',
  var bool running = true,
}) extends TerminalSessionHandle {
  @override
  final String tabId;

  int ensureStartedCallCount = 0;

  @override
  String get workspaceId => 'command-workspace';

  @override
  String get displayTitle => 'Command';

  @override
  late final ValueListenable<String> titleListenable = ValueNotifier<String>(
    displayTitle,
  );

  @override
  bool get isRunning => running;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCallCount += 1;
  }

  @override
  Future<void> restart() async {}

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}

/// Records what a command dialog asked the runtime for, so a test can assert
/// the working directory and the command that would reach the shell without
/// spawning anything.
class FakeCommandTerminalRuntime({final bool running = true})
    implements TerminalRuntime {
  final List<Workspace> workspaces = <Workspace>[];
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  final List<String> closedTabIds = <String>[];
  final Map<String, FakeCommandTerminalSession> sessions =
      <String, FakeCommandTerminalSession>{};
  final StreamController<TerminalRuntimeExitEvent> _exits =
      StreamController<TerminalRuntimeExitEvent>.broadcast();

  WorkspaceTabRecord? get lastTab => tabs.isEmpty ? null : tabs.last;

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exits.stream;

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    workspaces.add(workspace);
    tabs.add(tab);
    return sessions.putIfAbsent(
      tab.id,
      () => FakeCommandTerminalSession(tabId: tab.id, running: running),
    );
  }

  @override
  TerminalSessionHandle? peekSession(String tabId) => sessions[tabId];

  @override
  void setActiveWorkspace(String? workspaceId) {}

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    sessions.remove(tabId);
  }

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void releaseTab(String tabId) {
    sessions.remove(tabId);
  }

  @override
  void releaseWorkspace(String workspaceId) {}

  @override
  void dispose() {
    unawaited(_exits.close());
  }
}
