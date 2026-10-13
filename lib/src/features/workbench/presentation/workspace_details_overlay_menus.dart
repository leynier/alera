part of 'workspace_details_overlay.dart';

extension on _WorkspaceDetailsOverlayState {
  /// Opens Source Control in the right panel, or focuses it wherever the
  /// workspace already shows it.
  void _revealSourceControl() {
    ref.read(workbenchControllerProvider.notifier)
      ..setRightSidebarVisible(true)
      ..setContextPanelTab(.gitDiff);
  }

  Future<String?> _menu(Rect anchor, List<PopupMenuEntry<String>> entries) {
    return showMenu<String>(
      context: context,
      position: aleraMenuBelow(context, anchor),
      items: entries,
    );
  }

  Future<void> _detailsOptions(Rect anchor) async {
    final choice = await _menu(anchor, const [
      AleraDropdownEntry(
        value: 'host',
        label: 'Host And Hand Off',
        leading: _MenuIcon(AleraIcons.host),
      ),
      AleraDropdownEntry(
        value: 'open',
        label: 'Open In',
        leading: _MenuIcon(AleraIcons.folderOpen),
      ),
    ]);
    if (!mounted) return;
    if (choice == 'host') await _hostMenu(anchor);
    if (choice == 'open') await _openMenu(anchor);
  }

  Future<void> _hostMenu(Rect anchor) async {
    final workspace = widget.workspace;
    final choice = await _menu(anchor, [
      AleraDropdownEntry(
        value: 'handoff',
        label: 'Hand Off',
        leading: const _MenuIcon(AleraIcons.send),
        enabled: workspace.isMain,
      ),
    ]);
    if (choice == 'handoff' && mounted) {
      await showHandOffWorkspaceFlow(context, ref, workspace: workspace);
    }
  }

  Future<void> _openMenu(Rect anchor) async {
    final workspace = widget.workspace;
    final choice = await _menu(anchor, [
      AleraDropdownEntry(
        value: 'folder',
        label:
            'Open In ${ref.read(workspaceFolderOpenerProvider).fileManagerLabel}',
        leading: const _MenuIcon(AleraIcons.folderOpen),
        enabled: !workspace.isRemote,
      ),
      const AleraDropdownEntry(
        value: 'copy',
        label: 'Copy Path',
        leading: _MenuIcon(AleraIcons.copy),
      ),
      const AleraDropdownEntry(
        value: 'browser',
        label: 'Open In Browser',
        leading: _MenuIcon(AleraIcons.external),
      ),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'folder':
        await external_actions.openWorkspaceFolder(context, ref, workspace);
      case 'copy':
        await external_actions.copyWorkspacePath(context, workspace);
      case 'browser':
        await external_actions.openWorkspaceInBrowser(context, ref, workspace);
    }
  }
}

class const _MenuIcon(final IconData icon) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: AleraTokens.iconMd, color: AleraTokens.foregroundMuted);
}
