part of 'workspace_tabs_screen.dart';

extension _WorkspaceTabsActions on _WorkspaceTabsScreenState {
  Future<void> _renameTab(WorkspaceTabSummary tab) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AleraRenameDialog(
        title: 'Rename Tab',
        labelText: 'Tab Title',
        initialValue: tab.displayTitle,
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .renameTab(tab, title);
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not rename workspace tab.',
        error,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not rename tab: $error')));
      }
    }
  }

  Future<void> _showTabActions(
    WorkspaceTabSummary tab, {
    required bool canRename,
    required bool canGenerateTitle,
  }) async {
    final generating = tab.payload['agentTitleStatus'] == 'generating';
    final action = await showAleraActionSheet<_TabAction>(
      context,
      entries: <AleraActionSheetEntry<_TabAction>>[
        if (canRename)
          const AleraActionSheetEntry<_TabAction>(
            value: .rename,
            label: 'Rename Tab',
            leading: Icon(AleraIcons.edit),
          ),
        if (canGenerateTitle && tab.isTerminal)
          AleraActionSheetEntry<_TabAction>(
            value: .generateTitle,
            label: generating
                ? 'Generating title...'
                : tab.payload['agentTitleSource'] == 'generated'
                ? 'Regenerate Title'
                : 'Generate Title',
            leading: const Icon(AleraIcons.generate),
            enabled: !generating,
          ),
        if (tab.isTerminal)
          const AleraActionSheetEntry<_TabAction>(
            value: .close,
            label: 'Close Tab',
            leading: Icon(AleraIcons.close),
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _TabAction.generateTitle:
        await _generateTitle(tab);
      case _TabAction.rename:
        await _renameTab(tab);
      case _TabAction.close:
        await _closeTab(tab);
      case null:
        break;
    }
  }

  Future<void> _generateTitle(WorkspaceTabSummary tab) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .generateTitle(tab);
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not generate agent title.',
        error,
        stackTrace,
      );
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not generate title: $error')),
        );
      }
    }
  }
}

enum _TabAction { rename, generateTitle, close }
