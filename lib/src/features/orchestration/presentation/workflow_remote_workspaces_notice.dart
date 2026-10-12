import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

const String workflowRemoteWorkspacesNoticeMessage =
    'Workflows run on This Device. Remote workspaces are not listed.';

/// Whether a workspace picker for workflows hid any of
/// [workspaces] because they live on another host.
bool hidesRemoteWorkspaces(Iterable<Workspace> workspaces) =>
    workspaces.any((workspace) => isRemoteWorkspaceHostId(workspace.hostId));

/// Explains why remote workspaces are missing from a workflow picker. Callers
/// show it only when [hidesRemoteWorkspaces] filtered something out.
class const WorkflowRemoteWorkspacesNotice({
  super.key,
  final String message = workflowRemoteWorkspacesNoticeMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraInlineNotice(tone: .info, message: message);
  }
}
