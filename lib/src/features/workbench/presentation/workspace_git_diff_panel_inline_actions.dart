part of 'workspace_git_diff_panel.dart';

class const _GitFileActions({
  required final GitChangeEntry entry,
  required final bool busy,
  required final ValueChanged<GitChangeEntry> onStage,
  required final ValueChanged<GitChangeEntry> onUnstage,
  required final ValueChanged<GitChangeEntry> onDiscard,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: .end,
        children: <Widget>[
          if (entry.canUnstageFromParent)
            AleraIconButton(
              tooltip: 'Unstage',
              icon: AleraIcons.gitUnstage,
              onPressed: busy ? null : () => onUnstage(entry),
            )
          else if (entry.canStageFromParent)
            AleraIconButton(
              tooltip: 'Stage',
              icon: AleraIcons.gitStage,
              onPressed: busy ? null : () => onStage(entry),
            ),
          if (entry.canDiscardFromParent)
            AleraIconButton(
              tooltip: 'Discard',
              icon: AleraIcons.gitDiscard,
              onPressed: busy ? null : () => onDiscard(entry),
            ),
        ],
      ),
    );
  }
}

class const _AreaActions({
  required final bool busy,
  required final VoidCallback onStage,
  required final VoidCallback onUnstage,
  required final VoidCallback onDiscard,
  required final bool canStage,
  required final bool canUnstage,
  required final bool canDiscard,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: .end,
        children: <Widget>[
          if (canUnstage)
            AleraIconButton(
              tooltip: 'Unstage',
              icon: AleraIcons.gitUnstage,
              onPressed: busy ? null : onUnstage,
            )
          else if (canStage)
            AleraIconButton(
              tooltip: 'Stage',
              icon: AleraIcons.gitStage,
              onPressed: busy ? null : onStage,
            ),
          if (canDiscard)
            AleraIconButton(
              tooltip: 'Discard',
              icon: AleraIcons.gitDiscard,
              onPressed: busy ? null : onDiscard,
            ),
        ],
      ),
    );
  }
}
