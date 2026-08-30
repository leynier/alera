part of 'workspace_explorer.dart';

class const _ExplorerToolbar({
  required final String title,
  required final WorkspaceExplorerMode mode,
  required final bool loading,
  required final VoidCallback onRefresh,
  required final VoidCallback onCollapseAll,
  required final VoidCallback onToggleMode,
  required final VoidCallback onSaveAll,
  required final VoidCallback onNewFile,
  required final VoidCallback onNewFolder,
}) extends StatelessWidget {
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

class const _ExplorerRow({
  required final String name,
  required final native.WorkspaceFileEntry? entry,
  required final bool expanded,
  required final bool selected,
  required final bool sourceControlRoot,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .translucent,
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
                    overflow: .ellipsis,
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
                      message: 'Source control root',
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

class const _GitStatusIndicator({
  required final native.WorkspaceFileGitStatus status,
}) extends StatelessWidget {
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

class const _ExplorerNameDialog({
  required final String title,
  required final String label,
  required final String initialValue,
}) extends StatefulWidget {
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

class const _ExplorerMenuDelegate({
  required final String fileManagerLabel,
  required final bool canFocusSourceControlFolders,
  required final bool Function(tree.VisibleNode node)
  isFocusedSourceControlRoot,
  required final VoidCallback onMenuOpening,
  required final Future<void> Function(
    BuildContext context,
    tree.VisibleNode node,
    _ExplorerAction action,
  )
  onAction,
}) extends tree.ContextMenuDelegate {
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
        position: .fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: <PopupMenuEntry<_ExplorerAction>>[
          const AleraDropdownEntry<_ExplorerAction>(
            value: .newFile,
            label: 'New file',
            leading: Icon(AleraIcons.newFile, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .newFolder,
            label: 'New folder',
            leading: Icon(AleraIcons.newFolder, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .copy,
            label: 'Copy',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .cut,
            label: 'Cut',
            leading: Icon(AleraIcons.cut, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .paste,
            label: 'Paste',
            leading: Icon(AleraIcons.paste, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .copyPath,
            label: 'Copy path',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .copyRelativePath,
            label: 'Copy relative path',
            leading: Icon(AleraIcons.copy, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .duplicate,
            label: 'Duplicate',
            leading: Icon(AleraIcons.duplicate, size: 16),
          ),
          AleraDropdownEntry<_ExplorerAction>(
            value: .reveal,
            label: 'Reveal in $fileManagerLabel',
            leading: const Icon(AleraIcons.external, size: 16),
          ),
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .rename,
            label: 'Rename',
            leading: Icon(AleraIcons.edit, size: 16),
          ),
          if (canFocusSourceControlFolders &&
              node.type ==
                  tree.NodeType.folder) ...<PopupMenuEntry<_ExplorerAction>>[
            const PopupMenuDivider(height: AleraTokens.space8),
            if (isFocusedSourceControlRoot(node))
              const AleraDropdownEntry<_ExplorerAction>(
                value: .clearSourceControlRoot,
                label: 'Clear Source Control Root',
                leading: Icon(AleraIcons.close, size: 16),
              )
            else
              const AleraDropdownEntry<_ExplorerAction>(
                value: .focusSourceControlRoot,
                label: 'Use As Source Control Root',
                leading: Icon(AleraIcons.gitBranch, size: 16),
              ),
          ],
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .collapse,
            label: 'Collapse folder',
            leading: Icon(AleraIcons.chevronRight, size: 16),
          ),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .refresh,
            label: 'Refresh',
            leading: Icon(AleraIcons.refresh, size: 16),
          ),
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_ExplorerAction>(
            value: .delete,
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
      behavior: .translucent,
      onSecondaryTapDown: (details) => showMenuAt(details.globalPosition),
      onLongPressStart: (details) => showMenuAt(details.globalPosition),
      child: child,
    );
  }
}

class const _ExplorerBackgroundMenu({
  required final Widget child,
  required final bool Function() shouldSuppress,
  required final Future<void> Function(
    BuildContext context,
    _ExplorerAction action,
  )
  onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Future<void> showBackgroundMenu(Offset position) async {
      if (shouldSuppress()) {
        return;
      }
      final selected = await showMenu<_ExplorerAction>(
        context: context,
        position: .fromLTRB(position.dx, position.dy, position.dx, position.dy),
        items: const <PopupMenuEntry<_ExplorerAction>>[
          AleraDropdownEntry<_ExplorerAction>(
            value: .newFile,
            label: 'New file',
            leading: Icon(AleraIcons.newFile, size: 16),
          ),
          AleraDropdownEntry<_ExplorerAction>(
            value: .newFolder,
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
      behavior: .opaque,
      onPointerDown: (event) {
        if (event.buttons != kSecondaryMouseButton) {
          return;
        }
        unawaited(
          Future<void>.delayed(.zero, () {
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

class const _ExplorerClipboard(final String relativePath, final bool cut);

class const _ExplorerDragData({
  required final String relativePath,
  required final String absolutePath,
}) implements TerminalPathDragPayload {
  @override
  Iterable<String> get paths => <String>[absolutePath];
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
