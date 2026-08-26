part of 'workspace_git_diff_panel.dart';

class _GitFileActions extends StatelessWidget {
  const _GitFileActions({
    required this.entry,
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeEntry entry;
  final bool busy;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
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

class _AreaActions extends StatelessWidget {
  const _AreaActions({
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.canStage,
    required this.canUnstage,
    required this.canDiscard,
  });

  final bool busy;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final bool canStage;
  final bool canUnstage;
  final bool canDiscard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
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
