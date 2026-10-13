part of 'workspace_details_overlay.dart';

/// The workspace's parent and children, compared by what the row shows so
/// unrelated workbench changes do not rebuild the card.
class const _RelatedWorkspaces({this.parent, this.children = const []}) {
  final Workspace? parent;
  final List<Workspace> children;

  bool get isEmpty => parent == null && children.isEmpty;

  List<(String, String)> get _key => [
    for (final workspace in [?parent, ...children])
      (workspace.id, workspace.name),
  ];

  @override
  bool operator ==(Object other) =>
      other is _RelatedWorkspaces &&
      other.parent?.id == parent?.id &&
      listEquals(_key, other._key);

  @override
  int get hashCode => Object.hashAll(_key);
}

_RelatedWorkspaces _relatedWorkspaces(WorkbenchState state, String id) {
  final self = findWorkspaceById(state, id);
  final parentId = self?.hasParentWorkspace == true
      ? self!.parentWorkspaceId
      : null;
  final children = [
    for (final workspaces in state.workspacesByProject.values)
      for (final workspace in workspaces)
        if (workspace.parentWorkspaceId == id && !workspace.isArchived)
          workspace,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return _RelatedWorkspaces(
    parent: parentId == null ? null : findWorkspaceById(state, parentId),
    children: children,
  );
}

extension on _WorkspaceDetailsOverlayState {
  AleraWorkspaceDetailRow? _relatedRow(_RelatedWorkspaces related) {
    if (related.isEmpty) return null;
    final parent = related.parent;
    final count = related.children.length;
    final childLabel = count == 1
        ? '1 Child Workspace'
        : '$count Child Workspaces';
    return AleraWorkspaceDetailRow(
      label: parent != null ? 'Child of ${parent.name}' : childLabel,
      subtitle: parent != null && count > 0 ? childLabel : null,
      leading: const Icon(AleraIcons.workspaceChildren),
      hint: parent != null
          ? 'Open the parent workspace, ${parent.name}'
          : 'Open a child workspace',
      onPressed: parent == null
          ? null
          : () => unawaited(_openWorkspace(parent)),
      pressOpensMenu: parent == null,
      onMenu: (anchor) => unawaited(_relatedMenu(anchor, related)),
    );
  }

  Future<void> _relatedMenu(Rect anchor, _RelatedWorkspaces related) async {
    final parent = related.parent;
    final choice = await _menu(anchor, [
      if (parent != null)
        AleraDropdownEntry(
          value: parent.id,
          label: parent.name,
          detail: 'Parent',
          leading: const _MenuIcon(AleraIcons.back),
        ),
      if (parent != null && related.children.isNotEmpty)
        const PopupMenuDivider(),
      for (final child in related.children)
        AleraDropdownEntry(
          value: child.id,
          label: child.name,
          detail: child.branch,
          leading: const _MenuIcon(AleraIcons.workspaceChildren),
        ),
    ]);
    if (!mounted || choice == null) return;
    final target = [
      ?parent,
      ...related.children,
    ].where((workspace) => workspace.id == choice).firstOrNull;
    if (target != null) await _openWorkspace(target);
  }

  Future<void> _openWorkspace(Workspace target) async {
    final state = ref.read(workbenchControllerProvider);
    final project = findProjectById(state, target.projectId);
    if (project == null) return;
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: project, workspace: target);
  }
}
