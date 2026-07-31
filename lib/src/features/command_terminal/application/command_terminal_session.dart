import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';

/// Synthetic workspace backing every command session. `sessionFor` only reads
/// the id and the path, and neither this record nor the tab is ever persisted
/// or sent to the runtime host as a workbench tab.
Workspace buildCommandTerminalWorkspace({
  required String workingDirectory,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  return Workspace(
    id: commandTerminalWorkspaceId,
    projectId: commandTerminalWorkspaceId,
    name: 'Alera Command',
    path: workingDirectory,
    createdAt: timestamp,
    updatedAt: timestamp,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
  );
}

/// Synthetic tab carrying the command. Delivery is already handled Dart-side:
/// the session handle passes `initialCommand` to the startup delivery, which
/// writes it into the PTY once the shell is up.
///
/// The payload deliberately omits `spawnOnCreate` and `initialCommandOnce`.
/// Those are read by the runtime host off persisted tab records, and this
/// record never reaches it, so setting them would imply behavior that does not
/// happen here.
WorkspaceTabRecord buildCommandTerminalTab({
  required String tabId,
  required CommandTerminalRequest request,
  DateTime? now,
}) {
  final timestamp = now ?? DateTime.now();
  return WorkspaceTabRecord(
    id: tabId,
    workspaceId: commandTerminalWorkspaceId,
    title: request.title,
    createdAt: timestamp,
    updatedAt: timestamp,
    payload: <String, Object?>{
      workspaceTabTerminalSessionIdPayloadKey: tabId,
      workspaceTabManualTitlePayloadKey: true,
      workspaceTabInitialCommandPayloadKey: request.command,
    },
  );
}

/// Opens an ephemeral terminal session for [request].
///
/// The caller owns the session: it must call `runtime.closeTab(tabId)` when the
/// dialog goes away, which terminates the shell's whole process tree. Nothing
/// else will, because the workbench exit coordinator skips this workspace id.
TerminalSessionHandle openCommandTerminalSession({
  required TerminalRuntime runtime,
  required CommandTerminalRequest request,
  required String tabId,
  required String workingDirectory,
}) {
  return runtime.sessionFor(
    workspace: buildCommandTerminalWorkspace(
      workingDirectory: workingDirectory,
    ),
    tab: buildCommandTerminalTab(tabId: tabId, request: request),
  );
}
