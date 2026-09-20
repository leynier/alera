part of 'workspace_actions_sheet.dart';

List<Widget> _workspaceActionTiles(
  BuildContext context, {
  required WidgetRef ref,
  required String hostId,
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
  required bool hasDescendants,
  required bool hasTreeSection,
  required bool linkedIssueSupported,
  required bool hasLinkedIssue,
}) {
  final canRelocate =
      data.supportsWorkspaceRelocation &&
      data.projects.any(
        (project) =>
            project.id == workspace.projectId &&
            project.supportsLinkedWorkspaces,
      );
  final pairing = <Widget>[
    if (canRelocate)
      ListTile(
        leading: Icon(
          workspace.isMain ? AleraIcons.gitFork : AleraIcons.workspaceMain,
          size: 20,
        ),
        title: Text(workspace.isMain ? 'Hand Off' : 'Hand On'),
        onTap: () => Navigator.of(context).pop(_WorkspaceAction.relocate),
      ),
    if (canRelocate)
      ListTile(
        leading: const Icon(AleraIcons.restore, size: 20),
        title: const Text('Workspace Recovery'),
        onTap: () => Navigator.of(context).pop(_WorkspaceAction.recovery),
      ),
  ];
  final issue = _linkedIssueActionTiles(
    context,
    supported: linkedIssueSupported,
    linked: hasLinkedIssue,
  );
  return <Widget>[
    ListTile(
      leading: const Icon(AleraIcons.edit, size: 20),
      title: const Text('Rename'),
      onTap: () => Navigator.of(context).pop(_WorkspaceAction.rename),
    ),
    const Divider(height: 1),
    ...pairing,
    if (pairing.isNotEmpty) const Divider(height: 1),
    ..._pinActionTiles(
      context,
      workspace: workspace,
      hasDescendants: hasDescendants,
    ),
    ..._parentActionTiles(context, workspace: workspace),
    ..._sectionActionTiles(
      context,
      ref: ref,
      hostId: hostId,
      workspace: workspace,
      data: data,
      hasDescendants: hasDescendants,
      hasTreeSection: hasTreeSection,
    ),
    ListTile(
      leading: const Icon(AleraIcons.tag, size: 20),
      title: const Text('Manage Tags'),
      onTap: () => Navigator.of(context).pop(_WorkspaceAction.tags),
    ),
    const Divider(height: 1),
    ...issue,
    if (issue.isNotEmpty) const Divider(height: 1),
    ExpansionTile(
      leading: const Icon(AleraIcons.external, size: 20),
      title: const Text('Open'),
      children: <Widget>[
        ListTile(
          leading: const Icon(AleraIcons.external, size: 20),
          title: const Text('In Browser'),
          onTap: () =>
              Navigator.of(context).pop(_WorkspaceAction.openRepository),
        ),
      ],
    ),
    ListTile(
      leading: const Icon(AleraIcons.copy, size: 20),
      title: const Text('Copy Path'),
      onTap: () => Navigator.of(context).pop(_WorkspaceAction.copyPath),
    ),
    const Divider(height: 1),
    ListTile(
      leading: const Icon(AleraIcons.theme, size: 20),
      title: const Text('Sleep'),
      onTap: () => Navigator.of(context).pop(_WorkspaceAction.sleep),
    ),
    ..._archiveActionTiles(context, workspace: workspace, data: data),
    ListTile(
      leading: Icon(
        AleraIcons.delete,
        size: 20,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Remove',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      onTap: () => Navigator.of(context).pop(_WorkspaceAction.delete),
    ),
  ];
}

List<Widget> _pinActionTiles(
  BuildContext context, {
  required WorkspaceSummary workspace,
  required bool hasDescendants,
}) {
  final toggle = ListTile(
    leading: Icon(
      workspace.isPinned ? AleraIcons.pinOff : AleraIcons.pin,
      size: 20,
    ),
    title: Text(workspace.isPinned ? 'Unpin Workspace' : 'Pin Workspace'),
    onTap: () => Navigator.of(
      context,
    ).pop(workspace.isPinned ? _WorkspaceAction.unpin : _WorkspaceAction.pin),
  );
  if (!hasDescendants) {
    return <Widget>[toggle];
  }
  return <Widget>[
    ExpansionTile(
      leading: Icon(
        workspace.isPinned ? AleraIcons.pinOff : AleraIcons.pin,
        size: 20,
      ),
      title: const Text('Pin'),
      children: <Widget>[
        toggle,
        ListTile(
          leading: const Icon(AleraIcons.pin, size: 20),
          title: const Text('Pin Workspace Tree'),
          onTap: () => Navigator.of(context).pop(_WorkspaceAction.pinTree),
        ),
        ListTile(
          leading: const Icon(AleraIcons.pinOff, size: 20),
          title: const Text('Unpin Workspace Tree'),
          onTap: () => Navigator.of(context).pop(_WorkspaceAction.unpinTree),
        ),
      ],
    ),
  ];
}

List<Widget> _parentActionTiles(
  BuildContext context, {
  required WorkspaceSummary workspace,
}) {
  final setParent = ListTile(
    leading: const Icon(AleraIcons.link, size: 20),
    title: const Text('Set Parent Workspace'),
    onTap: () => Navigator.of(context).pop(_WorkspaceAction.configureParent),
  );
  if (!workspace.hasParent) {
    return <Widget>[setParent];
  }
  return <Widget>[
    ExpansionTile(
      leading: const Icon(AleraIcons.link, size: 20),
      title: const Text('Parent'),
      children: <Widget>[
        setParent,
        ListTile(
          leading: const Icon(AleraIcons.close, size: 20),
          title: const Text('Clear Parent Workspace'),
          onTap: () => Navigator.of(context).pop(_WorkspaceAction.unlinkParent),
        ),
      ],
    ),
  ];
}
