part of 'workspace_git_diff_panel.dart';

enum _GitChangeContextAction {
  openFile,
  revealInExplorer,
  stage,
  unstage,
  discard,
}

Future<void> _showGitChangeContextMenu(
  BuildContext context,
  Offset position, {
  required bool canOpenFile,
  required bool canStage,
  required bool canUnstage,
  required bool canDiscard,
  required bool busy,
  required VoidCallback? onOpenFile,
  required VoidCallback onRevealInExplorer,
  required VoidCallback onStage,
  required VoidCallback onUnstage,
  required VoidCallback onDiscard,
}) async {
  final selected = await showMenu<_GitChangeContextAction>(
    context: context,
    position: .fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: <PopupMenuEntry<_GitChangeContextAction>>[
      if (canOpenFile)
        const AleraDropdownEntry<_GitChangeContextAction>(
          value: .openFile,
          label: 'Open File',
          leading: Icon(AleraIcons.file, size: 16),
        ),
      const AleraDropdownEntry<_GitChangeContextAction>(
        value: .revealInExplorer,
        label: 'Reveal in Explorer',
        leading: Icon(AleraIcons.copyFiles, size: 16),
      ),
      if (canStage || canUnstage || canDiscard)
        const PopupMenuDivider(height: AleraTokens.space8),
      if (canUnstage)
        AleraDropdownEntry<_GitChangeContextAction>(
          value: .unstage,
          label: 'Unstage',
          leading: const Icon(AleraIcons.gitUnstage, size: 16),
          enabled: !busy,
        ),
      if (canStage)
        AleraDropdownEntry<_GitChangeContextAction>(
          value: .stage,
          label: 'Stage',
          leading: const Icon(AleraIcons.gitStage, size: 16),
          enabled: !busy,
        ),
      if (canDiscard)
        AleraDropdownEntry<_GitChangeContextAction>(
          value: .discard,
          label: 'Discard',
          leading: const Icon(AleraIcons.gitDiscard, size: 16),
          enabled: !busy,
        ),
    ],
  );
  if (selected == null || !context.mounted) {
    return;
  }
  switch (selected) {
    case _GitChangeContextAction.openFile:
      onOpenFile?.call();
    case _GitChangeContextAction.revealInExplorer:
      onRevealInExplorer();
    case _GitChangeContextAction.stage:
      onStage();
    case _GitChangeContextAction.unstage:
      onUnstage();
    case _GitChangeContextAction.discard:
      onDiscard();
  }
}
