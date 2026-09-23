part of 'workspace_actions_sheet.dart';

List<Widget> _archiveActionTiles(
  BuildContext context, {
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
}) {
  if (!data.supportsArchive) {
    return const <Widget>[];
  }
  final archived = workspace.isArchived;
  return <Widget>[
    ListTile(
      leading: Icon(
        archived ? AleraIcons.unarchive : AleraIcons.archive,
        size: 20,
      ),
      title: Text(archived ? 'Unarchive' : 'Archive'),
      onTap: () => Navigator.of(
        context,
      ).pop(archived ? _WorkspaceAction.unarchive : _WorkspaceAction.archive),
    ),
  ];
}

Future<void> _runArchiveAction(
  BuildContext context,
  WorkspaceListController controller, {
  required WorkspaceSummary workspace,
  required _WorkspaceAction action,
}) async {
  switch (action) {
    case _WorkspaceAction.archive:
      final confirmed = await showArchiveWorkspaceDialog(
        context,
        workspace: workspace,
      );
      if (confirmed) {
        await controller.archiveWorkspace(workspace.id);
      }
    case _WorkspaceAction.unarchive:
      await controller.unarchiveWorkspace(workspace.id);
    case _:
      throw StateError('Not an archive action: $action');
  }
}
