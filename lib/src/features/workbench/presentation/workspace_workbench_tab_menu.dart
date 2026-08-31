part of 'workspace_workbench_view.dart';

extension _WorkspaceTabMenu on _WorkspaceTabChip {
  Future<void> _openContextMenu(
    BuildContext context,
    Offset globalPosition,
    WidgetRef ref,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final tabIndex = groupTabs.indexWhere(
      (candidate) => candidate.id == tab.id,
    );
    final closeOthers = <String>[
      for (final candidate in groupTabs)
        if (candidate.id != tab.id) candidate.id,
    ];
    final closeRight = tabIndex < 0
        ? const <String>[]
        : <String>[
            for (final candidate in groupTabs.skip(tabIndex + 1)) candidate.id,
          ];
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_TabMenuAction>>[
        const AleraDropdownEntry<_TabMenuAction>(
          value: .splitUp,
          label: 'Split Up',
          leading: _SplitDirectionGlyph(zone: .up),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: .splitDown,
          label: 'Split Down',
          leading: _SplitDirectionGlyph(zone: .down),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: .splitLeft,
          label: 'Split Left',
          leading: _SplitDirectionGlyph(zone: .left),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: .splitRight,
          label: 'Split Right',
          leading: _SplitDirectionGlyph(zone: .right),
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        if (tab.isPreview && _KeepPreviewTabScope.maybeOf(context) != null)
          const AleraDropdownEntry<_TabMenuAction>(
            value: .keepOpen,
            label: 'Keep Open',
            leading: Icon(AleraIcons.pin, size: 16),
          ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: .close,
          label: 'Close',
          leading: Icon(AleraIcons.close, size: 16),
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: .closeOthers,
          label: 'Close Others',
          leading: Icon(
            AleraIcons.tabUnselected,
            size: 16,
            color: closeOthers.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeOthers.isNotEmpty,
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: .closeRight,
          label: 'Close Tabs to the Right',
          leading: Icon(
            AleraIcons.tab,
            size: 16,
            color: closeRight.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeRight.isNotEmpty,
        ),
        if ((tab.kind == WorkspaceTabKind.terminal ||
                tab.kind == WorkspaceTabKind.codex) &&
            ref.read(agentTitleAvailableProvider).value == true)
          AleraDropdownEntry<_TabMenuAction>(
            value: .generateTitle,
            label: agentTitleActionLabel(tab.payload),
            enabled: !isAgentTitleGenerating(tab.payload),
            leading: const Icon(AleraIcons.ai, size: 16),
          ),
        if (tab.kind !=
            WorkspaceTabKind.codex) ...<PopupMenuEntry<_TabMenuAction>>[
          const PopupMenuDivider(height: AleraTokens.space8),
          const AleraDropdownEntry<_TabMenuAction>(
            value: .changeTitle,
            label: 'Change Title',
            leading: Icon(AleraIcons.edit, size: 16),
          ),
        ],
      ],
    );
    if (selected == null || !context.mounted) {
      return;
    }
    switch (selected) {
      case _TabMenuAction.splitUp:
        onSplit(.up);
      case _TabMenuAction.splitDown:
        onSplit(.down);
      case _TabMenuAction.splitLeft:
        onSplit(.left);
      case _TabMenuAction.splitRight:
        onSplit(.right);
      case _TabMenuAction.keepOpen:
        _KeepPreviewTabScope.maybeOf(context)?.call(tab.id);
      case _TabMenuAction.close:
        onClose();
      case _TabMenuAction.closeOthers:
        onCloseTabs(closeOthers);
      case _TabMenuAction.closeRight:
        onCloseTabs(closeRight);
      case _TabMenuAction.generateTitle:
        try {
          await ref.read(agentTitleServiceProvider).generate(tab);
        } on Object catch (error) {
          AleraToast.publish(
            message: 'Could not generate title: $error',
            tone: .error,
          );
        }
      case _TabMenuAction.changeTitle:
        final title = await showRenameDialog(
          context,
          title: 'Change Terminal Title',
          labelText: 'Terminal Title',
          initialValue:
              terminalSession?.displayTitle ?? _workspaceTabTitle(tab),
          confirmLabel: 'Change Title',
        );
        if (title != null) {
          onRename(title);
        }
    }
  }
}
