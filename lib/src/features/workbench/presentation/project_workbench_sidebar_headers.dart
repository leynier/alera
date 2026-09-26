part of 'project_workbench_sidebar.dart';

class const _EmptyResultsView({required final String query})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final trimmed = query.trim();
    final message = trimmed.isEmpty
        ? 'No workspaces match the current filters'
        : 'No workspaces match "$trimmed"';
    return AleraEmptyState(message: message);
  }
}

/// Collapsible section header for the flat sidebar groupings (Pinned / All).
/// Mirrors the project header tile so the sections read as clear boundaries.
class const _SidebarSectionTile({
  required final IconData leadingIcon,
  required final String label,
  required final int count,
  required final bool expanded,
  required final VoidCallback onToggle,
  this.showTopDivider = false,
}) extends StatefulWidget {
  /// Draws a full-width divider above the header so the end of the previous
  /// section is visually marked.
  final bool showTopDivider;

  @override
  State<_SidebarSectionTile> createState() => _SidebarSectionTileState();
}

class _SidebarSectionTileState extends State<_SidebarSectionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (widget.showTopDivider)
          const Divider(height: 1, color: AleraTokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space2,
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: widget.onToggle,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: .circular(AleraTokens.radiusLg),
              child: AnimatedContainer(
                duration: AleraTokens.durationFast,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                  vertical: AleraTokens.space6,
                ),
                decoration: BoxDecoration(
                  color: _hovered ? AleraTokens.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      widget.leadingIcon,
                      size: 14,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _hovered
                              ? AleraTokens.foreground
                              : AleraTokens.foregroundMuted,
                          fontWeight: .w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Text(
                      widget.count.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundFaint,
                        fontWeight: .w500,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    Icon(
                      widget.expanded
                          ? AleraIcons.chevronUp
                          : AleraIcons.chevronDown,
                      size: 14,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class const _ProjectHeaderTile({
  required final Project project,
  required final bool expanded,
  required final int workspaceCount,
  required final VoidCallback onToggle,
  required final VoidCallback? onCreateWorkspace,
  required final VoidCallback onOpenProjectSettings,
  required final VoidCallback onRenameProject,
  required final VoidCallback onRemoveProject,

  /// Null hides the entry: folder projects live on one host, and an older
  /// runtime has no `project.hosts.*` verbs.
  required final VoidCallback? onManageHosts,
}) extends StatefulWidget {
  @override
  State<_ProjectHeaderTile> createState() => _ProjectHeaderTileState();
}

class _ProjectHeaderTileState extends State<_ProjectHeaderTile> {
  bool _hovered = false;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: .fromRect(
        .fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const AleraDropdownEntry<String>(
          value: _openProjectSettingsAction,
          leading: Icon(AleraIcons.settings, size: 16),
          label: 'Open Project Settings',
        ),
        const AleraDropdownEntry<String>(
          value: 'rename',
          leading: Icon(AleraIcons.edit, size: 16),
          label: 'Rename',
        ),
        if (widget.onManageHosts != null)
          const AleraDropdownEntry<String>(
            value: 'hosts',
            leading: Icon(AleraIcons.host, size: 16),
            label: 'Hosts',
          ),
        AleraDropdownEntry<String>(
          value: 'new-workspace',
          leading: Icon(
            AleraIcons.add,
            size: 16,
            color: widget.onCreateWorkspace == null
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          label: 'New Workspace',
          enabled: widget.onCreateWorkspace != null,
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: 'remove',
          leading: Icon(AleraIcons.delete, size: 16),
          label: 'Remove Project',
        ),
      ],
    );
    if (selected == _openProjectSettingsAction) {
      widget.onOpenProjectSettings();
    } else if (selected == 'rename') {
      widget.onRenameProject();
    } else if (selected == 'new-workspace') {
      widget.onCreateWorkspace?.call();
    } else if (selected == 'hosts') {
      widget.onManageHosts?.call();
    } else if (selected == 'remove') {
      widget.onRemoveProject();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          onTap: widget.onToggle,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusLg),
          child: AnimatedContainer(
            duration: AleraTokens.durationFast,
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            decoration: BoxDecoration(
              color: _hovered ? AleraTokens.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.expanded ? AleraIcons.folderOpen : AleraIcons.folder,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    widget.project.name,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _hovered
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  widget.workspaceCount.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                    fontWeight: .w500,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  widget.expanded
                      ? AleraIcons.chevronUp
                      : AleraIcons.chevronDown,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                if (widget.onCreateWorkspace != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space2),
                  AleraIconButton(
                    tooltip: 'New Workspace in This Project',
                    onPressed: widget.onCreateWorkspace!,
                    icon: AleraIcons.add,
                    iconSize: 14,
                    minSize: 24,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
