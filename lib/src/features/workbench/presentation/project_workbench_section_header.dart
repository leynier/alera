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
        AleraDropdownEntry(value: 'automations', label: 'Automations'),
        AleraDropdownEntry(
          value: 'new-automation',
          label: 'New Automation Here',
        ),
        PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry(value: 'delete', label: 'Delete Section'),
      ],
    );
    if (!context.mounted) return;
    final sectionScope = AutomationScope(
      kind: AutomationScopeKind.section,
      id: row.section!.id,
    );
    if (action == 'automations') {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(automationsNavigationProvider.notifier).open(scope: sectionScope);
      return;
    }
    if (action == 'new-automation') {
      ProviderScope.containerOf(context, listen: false)
          .read(automationsNavigationProvider.notifier)
          .startAuthoring(
            const AutomationAuthoringRequest(),
            scope: sectionScope,
          );
      return;
    }
    if (action != 'delete') return;
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
      leadingIcon: AleraIcons.section,
      label: row.label,
      count: row.workspaceCount,
      expanded: !row.collapsed,
      onToggle: () => controller.toggleSectionCollapsed(row.section?.id),
    ),
  );
}

Future<void> _saveWorkspaceSection(
  BuildContext context,
  WorkbenchController controller,
  Workspace workspace, {
  required bool tree,
  String? sectionId,
}) async {
  try {
    if (tree) {
      await controller.saveWorkspaceSectionTree(
        workspace.id,
        sectionId: sectionId,
      );
    } else {
      await controller.saveWorkspaceSection(workspace.id, sectionId: sectionId);
    }
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: sectionId == null
            ? 'Could not clear section: $error'
            : 'Could not set section: $error',
        tone: AleraToastTone.error,
      );
    }
  }
}
