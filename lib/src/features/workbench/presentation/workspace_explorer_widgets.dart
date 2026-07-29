part of 'workspace_explorer.dart';

class _ExplorerToolbar extends StatelessWidget {
  const _ExplorerToolbar({
    required this.title,
    required this.mode,
    required this.loading,
    required this.onRefresh,
    required this.onCollapseAll,
    required this.onToggleMode,
    required this.onSaveAll,
    required this.onNewFile,
    required this.onNewFolder,
  });

  final String title;
  final WorkspaceExplorerMode mode;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCollapseAll;
  final VoidCallback onToggleMode;
  final VoidCallback onSaveAll;
  final VoidCallback onNewFile;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            AleraIconButton(
              tooltip: 'New file',
              icon: AleraIcons.newFile,
              onPressed: onNewFile,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'New folder',
              icon: AleraIcons.newFolder,
              onPressed: onNewFolder,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Save all files',
              icon: AleraIcons.save,
              onPressed: onSaveAll,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: mode == WorkspaceExplorerMode.hideIgnored
                  ? 'Show ignored files'
                  : 'Hide ignored files',
              icon: mode == WorkspaceExplorerMode.hideIgnored
                  ? AleraIcons.hidden
                  : AleraIcons.visible,
              onPressed: onToggleMode,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Collapse All',
              icon: AleraIcons.collapseAll,
              onPressed: onCollapseAll,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: loading ? AleraIcons.loading : AleraIcons.refresh,
              onPressed: loading ? null : onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerRow extends StatelessWidget {
  const _ExplorerRow({
    required this.name,
    required this.entry,
    required this.expanded,
    required this.selected,
    required this.sourceControlRoot,
    required this.onTap,
  });

  final String name;
  final native.WorkspaceFileEntry? entry;
  final bool expanded;
  final bool selected;
  final bool sourceControlRoot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? AleraTokens.surfaceElevated : Colors.transparent,
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: AleraTokens.space8),
            child: Row(
              children: <Widget>[
                AleraFileIcon(
                  pathOrName: entry?.name ?? name,
                  kind: _iconKindFor(entry),
                  isExpanded: expanded,
                  size: 15,
                  fallbackColor: color,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: entry?.isProtected ?? false
                          ? AleraTokens.foregroundFaint
                          : color,
                    ),
                  ),
                ),
                if (entry?.gitStatus case final status?)
                  Padding(
                    padding: const EdgeInsets.only(left: AleraTokens.space8),
                    child: _GitStatusIndicator(status: status),
                  ),
                if (sourceControlRoot)
                  const Padding(
                    padding: EdgeInsets.only(left: AleraTokens.space8),
                    child: Tooltip(
                      message: 'Source Control Root',
                      child: Icon(
                        AleraIcons.gitBranch,
                        size: 14,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AleraFileIconKind _iconKindFor(native.WorkspaceFileEntry? entry) {
    if (entry == null) {
      return AleraFileIconKind.generic;
    }
    if (entry.isSymlink) {
      return AleraFileIconKind.symlink;
    }
    return switch (entry.kind.name) {
      'directory' => AleraFileIconKind.folder,
      'file' => AleraFileIconKind.file,
      'symlink' => AleraFileIconKind.symlink,
      'other' => AleraFileIconKind.generic,
      _ => AleraFileIconKind.generic,
    };
  }
}

class _GitStatusIndicator extends StatelessWidget {
  const _GitStatusIndicator({required this.status});

  final native.WorkspaceFileGitStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      native.WorkspaceFileGitStatus.untracked => ('U', AleraTokens.success),
      native.WorkspaceFileGitStatus.added => ('A', AleraTokens.success),
      native.WorkspaceFileGitStatus.modified => ('M', AleraTokens.warning),
    };
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    );
  }
}

class _ExplorerNameDialog extends StatefulWidget {
  const _ExplorerNameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_ExplorerNameDialog> createState() => _ExplorerNameDialogState();
}

class _ExplorerNameDialogState extends State<_ExplorerNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: AleraTextField(
        controller: _controller,
        labelText: widget.label,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ExplorerMenuDelegate extends tree.ContextMenuDelegate {
  const _ExplorerMenuDelegate({
    required this.fileManagerLabel,
    required this.canFocusSourceControlFolders,
    required this.isFocusedSourceControlRoot,
    required this.onMenuOpening,
    required this.onAction,
  });

  final String fileManagerLabel;
  final bool canFocusSourceControlFolders;
  final bool Function(tree.VisibleNode node) isFocusedSourceControlRoot;
  final VoidCallback onMenuOpening;
  final Future<void> Function(
    BuildContext context,
    tree.VisibleNode node,
    _ExplorerAction action,
  )
  onAction;

  @override
  List<tree.NodeAction> actionsFor(tree.VisibleNode node) =>
      const <tree.NodeAction>[];

  @override
  Widget wrapWithMenu(
    BuildContext context,
    Widget child,
    tree.VisibleNode node,
  ) {
    Future<void> showMenuAt(Offset position) async {
      onMenuOpening();
      final selected = await showMenu<_ExplorerAction>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: <PopupMenuEntry<_ExplorerAction>>[
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.newFile,
            label: 'New file',
            leading: Icon(AleraIcons.newFile, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.newFolder,
            label: 'New folder',
            leading: Icon(AleraIcons.newFolder, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.copy,
            label: 'Copy',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.cut,
            label: 'Cut',
            leading: Icon(AleraIcons.cut, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.paste,
            label: 'Paste',
            leading: Icon(AleraIcons.paste, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.copyPath,
            label: 'Copy path',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.copyRelativePath,
            label: 'Copy relative path',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.duplicate,
            label: 'Duplicate',
            leading: Icon(AleraIcons.duplicate, size: 16),
          ),
          AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.reveal,
            label: 'Reveal in $fileManagerLabel',
            leading: const Icon(AleraIcons.external, size: 16),
          ),
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.rename,
            label: 'Rename',
            leading: Icon(AleraIcons.edit, size: 16),
          ),
          if (canFocusSourceControlFolders &&
              node.type ==
                  tree.NodeType.folder) ...<PopupMenuEntry<_ExplorerAction>>[
            const PopupMenuDivider(height: AleraTokens.space8),
            if (isFocusedSourceControlRoot(node))
              const AleraDropdownEntry<_ExplorerAction>(
                value: _ExplorerAction.clearSourceControlRoot,
                label: 'Clear Source Control Root',
                leading: Icon(AleraIcons.close, size: 16),
              )
            else
              const AleraDropdownEntry<_ExplorerAction>(
                value: _ExplorerAction.focusSourceControlRoot,
                label: 'Use As Source Control Root',
                leading: Icon(AleraIcons.gitBranch, size: 16),
              ),
          ],
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.collapse,
            label: 'Collapse folder',
            leading: Icon(AleraIcons.chevronRight, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.refresh,
            label: 'Refresh',
            leading: Icon(AleraIcons.refresh, size: 16),
          ),
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.delete,
            label: 'Delete',
            leading: Icon(AleraIcons.delete, size: 16),
          ),
        ],
      );
      if (selected != null && context.mounted) {
        await onAction(context, node, selected);
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => showMenuAt(details.globalPosition),
      onLongPressStart: (details) => showMenuAt(details.globalPosition),
      child: child,
    );
  }
}

class _ExplorerBackgroundMenu extends StatelessWidget {
  const _ExplorerBackgroundMenu({
    required this.child,
    required this.shouldSuppress,
    required this.onAction,
  });

  final Widget child;
  final bool Function() shouldSuppress;
  final Future<void> Function(BuildContext context, _ExplorerAction action)
  onAction;

  @override
  Widget build(BuildContext context) {
    Future<void> showBackgroundMenu(Offset position) async {
      if (shouldSuppress()) {
        return;
      }
      final selected = await showMenu<_ExplorerAction>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: const <PopupMenuEntry<_ExplorerAction>>[
          AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.newFile,
            label: 'New file',
            leading: Icon(AleraIcons.newFile, size: 16),
          ),
          AleraDropdownEntry<_ExplorerAction>(
            value: _ExplorerAction.newFolder,
            label: 'New folder',
            leading: Icon(AleraIcons.newFolder, size: 16),
          ),
        ],
      );
      if (selected != null && context.mounted) {
        await onAction(context, selected);
      }
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons != kSecondaryMouseButton) {
          return;
        }
        unawaited(
          Future<void>.delayed(Duration.zero, () {
            if (context.mounted) {
              return showBackgroundMenu(event.position);
            }
          }),
        );
      },
      child: child,
    );
  }
}

class _ExplorerClipboard {
  const _ExplorerClipboard(this.relativePath, this.cut);

  final String relativePath;
  final bool cut;
}

class _ExplorerDragData {
  const _ExplorerDragData({required this.relativePath});

  final String relativePath;
}

enum _ExplorerAction {
  collapse,
  newFile,
  newFolder,
  rename,
  copy,
  cut,
  paste,
  copyPath,
  copyRelativePath,
  duplicate,
  reveal,
  delete,
  refresh,
  focusSourceControlRoot,
  clearSourceControlRoot,
}
