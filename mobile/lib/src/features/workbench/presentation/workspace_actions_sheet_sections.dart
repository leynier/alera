part of 'workspace_actions_sheet.dart';

const int _workspaceSectionSubmenuLimit = 10;

List<Widget> _sectionActionTiles(
  BuildContext context, {
  required WidgetRef ref,
  required String hostId,
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
  required bool hasDescendants,
  required bool hasTreeSection,
}) {
  if (!data.supportsSections) {
    return const <Widget>[];
  }
  Future<void> assign(String sectionId, bool tree) async {
    final controller = ref.read(
      workspaceListControllerProvider(hostId).notifier,
    );
    try {
      if (tree) {
        await controller.saveTreeSection(workspace.id, sectionId: sectionId);
      } else {
        await controller.setSection(workspace.id, sectionId);
      }
      if (context.mounted) {
        Navigator.pop(context);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workspace action failed: $error')),
        );
      }
    }
  }

  final sections = data.sections;
  final currentSectionId = workspace.sectionId;
  final hasSection = workspace.sectionId != null;
  if (sections.length < _workspaceSectionSubmenuLimit) {
    return <Widget>[
      _SectionSubmenuTile(
        title: 'Set Section',
        sections: sections,
        currentSectionId: currentSectionId,
        onAssign: (sectionId) => assign(sectionId, false),
        onNew: () => Navigator.pop(context, _WorkspaceAction.newSection),
      ),
      if (hasDescendants)
        _SectionSubmenuTile(
          title: 'Set Section Tree',
          sections: sections,
          currentSectionId: currentSectionId,
          onAssign: (sectionId) => assign(sectionId, true),
          onNew: () => Navigator.pop(context, _WorkspaceAction.newSectionTree),
        ),
      ..._clearSectionTiles(
        context,
        hasSection: hasSection,
        hasDescendants: hasDescendants,
        hasTreeSection: hasTreeSection,
      ),
    ];
  }
  return <Widget>[
    ListTile(
      leading: const Icon(AleraIcons.folder, size: 20),
      title: const Text('Set Section'),
      onTap: () => Navigator.pop(context, _WorkspaceAction.setSection),
    ),
    if (hasDescendants)
      ListTile(
        leading: const Icon(AleraIcons.folder, size: 20),
        title: const Text('Set Section Tree'),
        onTap: () => Navigator.pop(context, _WorkspaceAction.setSectionTree),
      ),
    ..._clearSectionTiles(
      context,
      hasSection: hasSection,
      hasDescendants: hasDescendants,
      hasTreeSection: hasTreeSection,
    ),
  ];
}

Future<void> _runSectionAction(
  BuildContext context,
  WorkspaceListController controller, {
  required String hostId,
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
  required _WorkspaceAction action,
}) async {
  switch (action) {
    case _WorkspaceAction.setSection:
      await showSectionPickerSheet(
        context,
        hostId: hostId,
        workspace: workspace,
        workspaces: data.workspaces,
      );
    case _WorkspaceAction.setSectionTree:
      await showSectionPickerSheet(
        context,
        hostId: hostId,
        workspace: workspace,
        workspaces: data.workspaces,
        applyToTree: true,
      );
    case _WorkspaceAction.newSection:
      await showSectionPickerSheet(
        context,
        hostId: hostId,
        workspace: workspace,
        workspaces: data.workspaces,
        createMode: true,
      );
    case _WorkspaceAction.newSectionTree:
      await showSectionPickerSheet(
        context,
        hostId: hostId,
        workspace: workspace,
        workspaces: data.workspaces,
        applyToTree: true,
        createMode: true,
      );
    case _WorkspaceAction.clearSection:
      await controller.setSection(workspace.id, null);
    case _WorkspaceAction.clearSectionTree:
      await controller.saveTreeSection(workspace.id);
    default:
      break;
  }
}

List<Widget> _clearSectionTiles(
  BuildContext context, {
  required bool hasSection,
  required bool hasDescendants,
  required bool hasTreeSection,
}) {
  return <Widget>[
    if (hasSection)
      ListTile(
        leading: const Icon(AleraIcons.folderOff, size: 20),
        title: const Text('Clear Section'),
        onTap: () => Navigator.pop(context, _WorkspaceAction.clearSection),
      ),
    if (hasDescendants && hasTreeSection)
      ListTile(
        leading: const Icon(AleraIcons.folderOff, size: 20),
        title: const Text('Clear Section Tree'),
        onTap: () => Navigator.pop(context, _WorkspaceAction.clearSectionTree),
      ),
  ];
}

class const _SectionSubmenuTile({
  required final String title,
  required final List<WorkspaceSectionSummary> sections,
  required final String? currentSectionId,
  required final Future<void> Function(String sectionId) onAssign,
  required final VoidCallback onNew,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(AleraIcons.folder, size: 20),
      title: Text(title),
      children: <Widget>[
        for (final section in sections)
          ListTile(
            title: Text(section.name),
            trailing: section.id == currentSectionId
                ? const Icon(AleraIcons.check, size: 20)
                : null,
            onTap: () => onAssign(section.id),
          ),
        ListTile(
          leading: const Icon(AleraIcons.add, size: 20),
          title: const Text('New Section'),
          onTap: onNew,
        ),
      ],
    );
  }
}
