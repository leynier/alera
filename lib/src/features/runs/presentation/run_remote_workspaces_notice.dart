import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

const String runRemoteWorkspacesNoticeMessage =
    'Runs use workspaces on This Device. Remote workspaces are not listed.';

/// Whether a workspace picker for runs hid any of
/// [workspaces] because they live on another host.
bool hidesRemoteWorkspaces(Iterable<Workspace> workspaces) =>
    workspaces.any((workspace) => isRemoteWorkspaceHostId(workspace.hostId));

/// Explains why remote workspaces are missing from a run or recipe picker. Callers
/// show it only when [hidesRemoteWorkspaces] filtered something out.
class const RunRemoteWorkspacesNotice({
  super.key,
  final String message = runRemoteWorkspacesNoticeMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraInlineNotice(tone: .info, message: message);
  }
}
