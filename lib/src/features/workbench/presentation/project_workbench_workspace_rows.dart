part of 'project_workbench_sidebar.dart';

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    required this.project,
    required this.workspace,
    required this.agentRunCount,
    required this.status,
    required this.hasTerminalTabs,
    required this.isActive,
    required this.showProjectChip,
    required this.expanded,
    required this.onTap,
    required this.onOpenFolder,
    required this.onCopyPath,
    required this.onSleep,
    required this.onToggleExpanded,
    required this.fileManagerLabel,
    required this.onRename,
    this.onDelete,
  });

  final Project project;
  final Workspace workspace;
  final int agentRunCount;
  final AgentStatusEntry? status;
  final bool hasTerminalTabs;
  final bool isActive;
  final bool showProjectChip;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyPath;
  final VoidCallback onSleep;
  final VoidCallback onToggleExpanded;
  final String fileManagerLabel;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  static const String _renameAction = 'rename';
  static const String _openFolderAction = 'open-folder';
  static const String _copyPathAction = 'copy-path';
  static const String _sleepAction = 'sleep';
  static const String _removeAction = 'remove';

  bool _hovered = false;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const AleraDropdownEntry<String>(
          value: _renameAction,
          leading: Icon(AleraIcons.edit, size: 16),
          label: 'Rename',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        AleraDropdownEntry<String>(
          value: _openFolderAction,
          leading: const Icon(
            AleraIcons.folderOpen,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Open in ${widget.fileManagerLabel}',
        ),
        const AleraDropdownEntry<String>(
          value: _copyPathAction,
          leading: Icon(
            AleraIcons.copy,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Copy Path',
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<String>(
          value: _sleepAction,
          leading: Icon(
            AleraIcons.theme,
            size: 16,
            color: AleraTokens.foreground,
          ),
          label: 'Sleep',
        ),
        AleraDropdownEntry<String>(
          value: _removeAction,
          leading: Icon(
            AleraIcons.delete,
            size: 16,
            color: widget.onDelete != null
                ? AleraTokens.foreground
                : AleraTokens.foregroundFaint,
          ),
          label: 'Remove',
          enabled: widget.onDelete != null,
        ),
      ],
    );

    if (selected == _renameAction) {
      widget.onRename();
    } else if (selected == _openFolderAction) {
      widget.onOpenFolder();
    } else if (selected == _copyPathAction) {
      widget.onCopyPath();
    } else if (selected == _sleepAction) {
      widget.onSleep();
    } else if (selected == _removeAction) {
      widget.onDelete?.call();
    }
  }

  String _buildSecondaryLine() {
    final branch = widget.workspace.branch;
    final parts = <String>[
      if (branch != null && branch.isNotEmpty)
        branch
      else if (widget.project.isFolder)
        'Local Folder'
      else
        'Git Repository',
    ];
    final source = widget.workspace.sourceBranch;
    if (!widget.workspace.isMain &&
        !widget.workspace.reusesExistingBranch &&
        source != null &&
        source.isNotEmpty) {
      parts.add('Base: $source');
    }
    if (widget.agentRunCount > 0) {
      parts.add(
        widget.agentRunCount == 1
            ? '1 Agent Run'
            : '${widget.agentRunCount} Agent Runs',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
          child: AnimatedContainer(
            duration: AleraTokens.durationMid,
            decoration: BoxDecoration(
              color: isActive
                  ? AleraTokens.surfaceElevated
                  : (_hovered ? AleraTokens.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: InkWell(
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                  vertical: AleraTokens.space8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: widget.status == null
                          ? AleraStatusDot(
                              active: isActive || widget.hasTerminalTabs,
                            )
                          : _AgentRunStateIndicator(status: widget.status!),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  widget.workspace.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AleraTokens.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (widget.workspace.isMain) ...<Widget>[
                                const SizedBox(width: AleraTokens.space6),
                                const AleraBadge(label: 'Primary'),
                              ],
                            ],
                          ),
                          const SizedBox(height: AleraTokens.space4),
                          Row(
                            children: <Widget>[
                              if (widget.showProjectChip) ...<Widget>[
                                Flexible(
                                  child: AleraChip(label: widget.project.name),
                                ),
                                const SizedBox(width: AleraTokens.space6),
                              ],
                              Flexible(
                                child: Text(
                                  _buildSecondaryLine(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AleraTokens.foregroundFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.agentRunCount > 0)
                      AleraIconButton(
                        tooltip: widget.expanded
                            ? 'Hide Agent Runs'
                            : 'Show Agent Runs',
                        onPressed: widget.onToggleExpanded,
                        icon: widget.expanded
                            ? AleraIcons.chevronUp
                            : AleraIcons.chevronDown,
                        iconSize: 14,
                        minSize: 24,
                      ),
                    if (widget.onDelete != null)
                      IgnorePointer(
                        ignoring: !actionsVisible,
                        child: AnimatedOpacity(
                          opacity: actionsVisible ? 1 : 0,
                          duration: AleraTokens.durationFast,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: AleraTokens.space2,
                            ),
                            child: AleraIconButton(
                              tooltip: 'Remove Workspace',
                              onPressed: widget.onDelete!,
                              icon: AleraIcons.delete,
                              iconSize: 14,
                              minSize: 24,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
