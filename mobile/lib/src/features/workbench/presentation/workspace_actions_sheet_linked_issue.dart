part of 'workspace_actions_sheet.dart';

/// Issue entries: none without host support, `Link Issue` without a link, and
/// open, change and unlink with one.
List<Widget> _linkedIssueActionTiles(
  BuildContext context, {
  required bool supported,
  required bool linked,
}) {
  if (!supported) {
    return const <Widget>[];
  }
  ListTile tile(IconData icon, String title, _WorkspaceAction action) =>
      ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        onTap: () => Navigator.of(context).pop(action),
      );
  if (!linked) {
    return <Widget>[
      tile(AleraIcons.issueUnknown, 'Link Issue', _WorkspaceAction.linkIssue),
    ];
  }
  return <Widget>[
    tile(
      AleraIcons.external,
      'Open Issue in Browser',
      _WorkspaceAction.openIssue,
    ),
    tile(AleraIcons.link, 'Change Linked Issue', _WorkspaceAction.changeIssue),
    tile(AleraIcons.unlink, 'Unlink Issue', _WorkspaceAction.unlinkIssue),
  ];
}

Future<bool> _confirmUnlinkIssue(
  BuildContext context,
  WorkspaceSummary workspace,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unlink Issue?'),
      content: Text(
        'This removes the issue link from ${workspace.name}. The issue itself will not be changed.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Unlink Issue'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> _runLinkedIssueAction(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceSummary workspace,
  required String? url,
  required _WorkspaceAction action,
}) async {
  switch (action) {
    case _WorkspaceAction.openIssue:
      final uri = Uri.tryParse(url ?? '');
      if (uri == null || !await launchUrl(uri)) {
        throw StateError('The linked issue URL could not be opened.');
      }
    case _WorkspaceAction.unlinkIssue:
      if (await _confirmUnlinkIssue(context, workspace)) {
        await ref
            .read(linkedIssuesControllerProvider(hostId).notifier)
            .unlink(workspace.id);
      }
    default:
      final result = await showMobileLinkIssueDialog(
        context,
        hostId: hostId,
        workspaceId: workspace.id,
        initialUrl: action == _WorkspaceAction.changeIssue ? url : null,
      );
      if (result != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mobileLinkIssueMessage(result))));
      }
  }
}
