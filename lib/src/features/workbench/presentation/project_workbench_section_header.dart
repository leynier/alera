part of 'project_workbench_sidebar.dart';

class _WorkspaceSectionHeader extends StatelessWidget {
  const _WorkspaceSectionHeader({required this.row, required this.controller});
  final WorkbenchSectionHeaderRow row;
  final WorkbenchController controller;

  Future<void> _menu(BuildContext context, Offset position) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: const [
        AleraDropdownEntry(value: 'delete', label: 'Delete Section'),
      ],
    );
    if (action != 'delete' || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Delete Section?',
        message:
            'Delete "${row.label}"? Its workspaces will be preserved and moved to Others.',
        confirmLabel: 'Delete Section',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteWorkspaceSection(row.section!.id);
    } catch (error) {
      if (context.mounted) {
        AleraToast.show(
          context,
          message: 'Could not delete section: $error',
          tone: AleraToastTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapDown: row.section == null
        ? null
        : (event) => _menu(context, event.globalPosition),
    child: _SidebarSectionTile(
      leadingIcon: AleraIcons.folder,
      label: row.label,
      count: row.workspaceCount,
      expanded: !row.collapsed,
      onToggle: () => controller.toggleSectionCollapsed(row.section?.id),
    ),
  );
}

Future<void> _clearSection(
  BuildContext context,
  WorkbenchController controller,
  Workspace workspace,
) async {
  try {
    await controller.saveWorkspaceSection(workspace.id);
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: 'Could not clear section: $error',
        tone: AleraToastTone.error,
      );
    }
  }
}
